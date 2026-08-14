import { QueryClient } from "@tanstack/react-query";
import { createRouter } from "@tanstack/react-router";
import { routeTree } from "./routeTree.gen";

export const getRouter = () => {
  // Static dashboard configuration (World Cup finished)
  // Disable all automatic refetching since data won't change
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: Infinity,           // Data never goes stale
        gcTime: Infinity,              // Keep in cache forever (was cacheTime)
        refetchOnWindowFocus: false,   // Don't refetch when user returns to tab
        refetchOnReconnect: false,     // Don't refetch when internet reconnects
        refetchOnMount: false,         // Don't refetch when component mounts
        retry: 1,                      // Only retry once on failure
      },
    },
  });

  const router = createRouter({
    routeTree,
    context: { queryClient },
    scrollRestoration: true,
    defaultPreloadStaleTime: 0,
  });

  return router;
};
