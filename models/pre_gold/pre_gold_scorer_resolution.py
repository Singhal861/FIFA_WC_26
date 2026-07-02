import subprocess
from pyspark.sql import functions as F

def model(dbt, spark):
    """
    Pre-gold gate: Ensures all scorers are resolved before gold layer.
    Flow:
    1. Run pre-gold test
    2. If FAILS: INSERT PENDING → Call AI Notebook → Retry test ONCE
    3. If PASSES: Continue
    4. If still fails after AI: Pipeline FAILS (no loop)
    """
    
    # Step 1: Run pre-gold test
    print("🔍 Running pre-gold test: test_scorer_mapping_complete")
    print("="*60)
    
    result = subprocess.run(
        ["dbt", "test", "--select", "test_scorer_mapping_complete"],
        cwd="/Workspace/Users/abhisheksinghal861@gmail.com/Data-Pipelines",
        capture_output=True,
        text=True
    )
    
    test_passed = (result.returncode == 0)
    
    if test_passed:
        print("✅ Pre-gold test PASSED - All scorers RESOLVED")
        return spark.createDataFrame([{"status": "PASSED", "action": "NONE"}])
    
    # Step 2: Test FAILED - Insert PENDING scorers
    print("❌ Pre-gold test FAILED - Found unmapped scorers")
    print("📝 Inserting unmapped scorers as PENDING...")
    
    goal_events = dbt.ref("silver_goal_events")
    mapping = dbt.ref("silver_player_name_mapping")
    
    # Find unmapped scorers
    distinct_scorers = goal_events.select(
        F.col("scorer_name"),
        F.col("team_name"),
        F.col("team_id")
    ).distinct()
    
    unmapped = distinct_scorers.join(
        mapping.select("scorer_name"),
        "scorer_name",
        "left_anti"
    )
    
    unmapped_count = unmapped.count()
    print(f"⚠️ Found {unmapped_count} unmapped scorers")
    
    if unmapped_count > 0:
        # INSERT as PENDING
        pending_records = unmapped.select(
            F.col("scorer_name"),
            F.lit(None).cast("string").alias("player_id"),
            F.lit(None).cast("string").alias("player_name"),
            F.col("team_id"),
            F.col("team_name"),
            F.lit("PENDING").alias("status"),
            F.lit(None).cast("string").alias("match_method"),
            F.lit(None).cast("float").alias("confidence"),
            F.current_timestamp().alias("created_at"),
            F.lit(None).cast("timestamp").alias("resolved_at")
        )
        
        pending_records.write.mode("append").saveAsTable(
            "singhal.fifa_worldcup_silver.silver_player_name_mapping"
        )
        print(f"✅ Inserted {unmapped_count} scorers as PENDING")
    
    # Step 3: Call AI Notebook
    print("🤖 Calling AI Name Resolver notebook...")
    print("   Path: /Users/abhisheksinghal861@gmail.com/Databricks_core_notebooks/Optimization_layer/AI_Player_Name_Resolver")
    
    from databricks.sdk.runtime import dbutils
    
    ai_result = dbutils.notebook.run(
        "/Users/abhisheksinghal861@gmail.com/Databricks_core_notebooks/Optimization_layer/AI_Player_Name_Resolver",
        timeout_seconds=1800  # 30 minutes for AI processing
    )
    print(f"✅ AI resolution completed")
    
    # Step 4: RETRY test ONCE (no loop)
    print("🔄 RETRYING pre-gold test (ONE TIME ONLY - no loop)...")
    print("="*60)
    
    result_retry = subprocess.run(
        ["dbt", "test", "--select", "test_scorer_mapping_complete"],
        cwd="/Workspace/Users/abhisheksinghal861@gmail.com/Data-Pipelines",
        capture_output=True,
        text=True
    )
    
    if result_retry.returncode == 0:
        print("✅ Pre-gold test PASSED after AI resolution!")
        return spark.createDataFrame([{"status": "PASSED", "action": "AI_RESOLVED"}])
    else:
        print("❌ Pre-gold test STILL FAILED after AI resolution")
        print("⚠️ Manual intervention needed - check AI notebook output")
        raise Exception(
            "Pre-gold validation failed after AI resolution. "
            "Some scorers could not be matched. Check mapping table for PENDING records."
        )

# dbt config
def config():
    return {
        "materialized": "table",
        "tags": ["pre_gold", "gate", "validation"]
    }