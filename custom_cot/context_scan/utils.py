import httpx

from anthropic import AsyncAnthropic
from openai import OpenAI
from dotenv import load_dotenv
import os
import instructor

# # BaseTaskManager batch size to 1
#     @final
#     async def _run_ingested_context_scans(self) -> None:
#         """Run ingested‐context scans in a single batch for quick testing."""
#         # 1. Only zero-shot profile for test
#         all_configs = self.ingested_context_scan_configs or []
#         configs = [c for c in all_configs if c["profile"] == Profiles.NONE]

#         total = len(configs)
#         if total == 0:
#             return

#         # 2. One big batch
#         logger.info(f"[TaskManager] Running 1 ingested‐context scan batch (zero-shot only)")
#         await self._run_ingested_context_scan_batch(configs)

#         # 3. Throttle
#         await asyncio.sleep(1)

load_dotenv(); ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")

def get_claude_client():
    """Get a configured Claude client instance with instructor integration."""
    try:
        timeout = httpx.Timeout(300.0, connect=10.0)  # 5 minutes total, 10s connect
        limits = httpx.Limits(max_keepalive_connections=5, max_connections=10)
        http_client = httpx.AsyncClient(timeout=timeout, limits=limits)
        base_claude_client = AsyncAnthropic(
            api_key=ANTHROPIC_API_KEY,
            http_client=http_client,
        )
        claude_client = instructor.from_anthropic(
            base_claude_client, mode=instructor.Mode.ANTHROPIC_REASONING_TOOLS
        )
        return claude_client
    except Exception as e:
        logger.error(f"[LLMClient] Failed to initialize Claude client: {str(e)}", exc_info=True)
        raise
