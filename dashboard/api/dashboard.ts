import type { VercelRequest, VercelResponse } from "@vercel/node";

const HOST = process.env.DATABRICKS_HOST!;
const TOKEN = process.env.DATABRICKS_TOKEN!;
const WAREHOUSE_ID = process.env.DATABRICKS_WAREHOUSE_ID!;

async function executeSQL(statement: string) {
  const response = await fetch(
    `https://${HOST}/api/2.0/sql/statements`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        warehouse_id: WAREHOUSE_ID,
        statement,
        wait_timeout: "30s",
      }),
    }
  );

  const json = await response.json();

  if (!response.ok) {
    console.error("Databricks Error:", json);
    throw new Error(JSON.stringify(json, null, 2));
  }

  // Convert Databricks response to array of objects
  const columns = json.manifest.schema.columns.map((c: any) => c.name);

  return json.result.data_array.map((row: any[]) => {
    const obj: Record<string, any> = {};

    columns.forEach((col: string, index: number) => {
      obj[col] = row[index];
    });

    return obj;
  });
}

export default async function handler(
  req: VercelRequest,
  res: VercelResponse
) {
  try {
    const summary = await executeSQL(`
      SELECT *
      FROM singhal.fifa_worldcup_gold.gold_tournament_summary
    `);

    res.setHeader(
      "Cache-Control",
      "s-maxage=900, stale-while-revalidate=300"
    );

    return res.status(200).json({
      success: true,
      summary,
    });
  } catch (error: any) {
    console.error(error);

    return res.status(500).json({
      success: false,
      error: error.message,
    });
  }
}