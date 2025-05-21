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
        print(f"[LLMClient] Failed to initialize Claude client: {str(e)}", exc_info=True)
        raise


#-------------------org context ingestion-----------------------------


# from typing import Optional, List, Tuple, Union
# from langfuse.decorators import observe

# from api.v1.utilities.context_ingestion.schema import ContextIngestionResponse
# from api.v1.utilities.invariants.schema import InvariantsResponse
# from config.settings import LLM_UTILITY_2
# from config.prompts.context_ingestion_prompts import INGESTION_SYSTEM_PROMPT
# from core.llm.send_prompt_to_llm import send_prompt_to_llm_async
# from core.llm.prompt_builder import PromptBuilder
# from core.utils.logger import logger
# from core.utils.profiles import Profiles
# from core.utils.errors import LLMError, ValidationError
# import json


# _prompt_builder = PromptBuilder()

# @observe(name="[Context Ingestion] Generate structured context")
# async def generate_context_ingestion(
#     contracts: str,
#     summary: Optional[str],
#     docs: Optional[str],
#     invariants: Optional[InvariantsResponse],
#     web_search_results: Optional[str] = None,
#     model: str = LLM_UTILITY_2,
# ) -> ContextIngestionResponse:
#     """
#     Consume all project and code context (summary, docs, invariants,
#     web search, flattened contracts) and return a fully-structured
#     ContextIngestionResponse according to our Pydantic schema.

#     Args:
#         contracts (str): Flattened Solidity code for the entire project.
#         summary (Optional[str]): Summary of the project
#         docs (Optional[str]): Documentation for the project
#         invariants (Optional[InvariantsResponse]): Invariants response
#         web_search_results (Optional[str], optional): Web search results. Defaults to None.
#         model (str, optional): LLM model for the task. Defaults to LLM_UTILITY_2.

#     Raises:
#         ValidationError: If the LLM returns no data or missing key fields.
#         ValidationError: If contract context ingestion map is missing.
#         LLMError: On unexpected failures calling the LLM or parsing.
#     """
#     logger.info("[Context Ingestion] Starting context ingestion task...")
#     try:
#         # Build context ingestion prompt
#         formatted_prompt = _prompt_builder.build_context_ingestion_prompt(
#         summary=summary,
#         docs=docs,
#         invariants=invariants,
#         web_search_results=web_search_results,
#         flattened_contracts=contracts,
#     )

#         # Build full messages with profile
#         messages = _prompt_builder.build_messages(
#             model_type=model,
#             user_input=formatted_prompt,
#             system_prompt=INGESTION_SYSTEM_PROMPT,
#             profile=None,
#         )

#         # Send to LLM for structured output
#         llm_response = await send_prompt_to_llm_async(
#             model_type=LLM_UTILITY_2,
#             messages=messages,
#             response_model=ContextIngestionResponse,
#         )

#         # Validate minimal contract-level data is present
#         if not llm_response or not isinstance(llm_response, ContextIngestionResponse):
#             logger.warning("[Context Ingestion] LLM response was empty or invalid")
#             raise ValidationError(
#                 message="Invalid LLM response for context ingestion",
#                 details={"error": "Response was empty or wrong type"},
#             )

#         if not llm_response.analyzed_contracts:
#             logger.warning("[Context Ingestion] No contracts extracted from LLM response")
#             raise ValidationError(
#                 message="Context ingestion produced no contract summaries",
#                 details={"error": "analyzed_contracts is empty"},
#             )
#         # Return the parsed, validated context summary
#         logger.info(f"[Context Ingestion] Context ingestion successfully completed. Contracts processed: {len(llm_response.analyzed_contracts)}")
#         return llm_response

#     except (LLMError, ValidationError):
#         raise

#     except Exception as e:
#         logger.exception(f"[Context Ingestion] Unexpected error in generate_context_summary: {e}")
#         raise LLMError(
#             message="Unexpected error during context ingestion",
#             details={"error": str(e)},
#         ) from e

#-------------------chunking context ingestion-----------------------------
# import gc
# import re
# from typing import List, Optional

# from langfuse.decorators import observe

# from api.v1.utilities.context_ingestion.schema import ContextIngestionResponse
# from api.v1.utilities.invariants.schema import InvariantsResponse
# from config.prompts.context_ingestion_prompts import INGESTION_SYSTEM_PROMPT
# from config.settings import LLM_UTILITY_2
# from core.llm.prompt_builder import PromptBuilder
# from core.llm.send_prompt_to_llm import send_prompt_to_llm_async
# from core.utils.errors import LLMError, ValidationError
# from core.utils.logger import logger

# _prompt_builder = PromptBuilder()

# # Number of contracts to process in each batch
# CHUNK_SIZE = 5


# def _split_flattened_contracts(flattened: str, n: int) -> List[str]:
#     """
#     Split a long string of flattened contracts into chunks.
#     Each chunk contains up to `chunk_size` individual contracts, joined by double newlines.
#     Contracts are expected to start with the marker "// File:".
#     """
#     # contracts start with "// File:"  (our flattener’s convention)
#     parts = re.split(r"(?=\/\/ File:)", flattened)
#     parts = [p.strip() for p in parts if p.strip()]
#     chunks: List[str] = []
#     for i in range(0, len(parts), n):
#         chunks.append("\n\n".join(parts[i : i + n]))
#     return chunks


# def merge_contract_analysis(
#     target_response: Optional[ContextIngestionResponse],
#     new_response: ContextIngestionResponse,
# ) -> ContextIngestionResponse:
#     """
#     Merge two ContextIngestionResponse objects by appending
#     any newly analyzed contracts (avoiding duplicates by file name).
#     """
#     if target_response is None:
#         return new_response

#     seen_files = {c.file_name for c in target_response.analyzed_contracts}
#     for contract in new_response.analyzed_contracts:
#         if contract.file_name not in seen_files:
#             target_response.analyzed_contracts.append(contract)
#             seen_files.add(contract.file_name)
#     return target_response


# async def ingest_contract_chunk(
#     contracts_chunk: str,
#     summary: Optional[str],
#     docs: Optional[str],
#     invariants: Optional[InvariantsResponse],
#     web_search_results: Optional[str],
#     model: str,
# ) -> ContextIngestionResponse:
#     """
#     Consume all project and code context (summary, docs, invariants,
#     web search, flattened contracts) and return a fully-structured
#     ContextIngestionResponse according to our Pydantic schema.

#     Args:
#         contracts (str): Flattened Solidity code for the entire project.
#         summary (Optional[str]): Summary of the project
#         docs (Optional[str]): Documentation for the project
#         invariants (Optional[InvariantsResponse]): Invariants response
#         web_search_results (Optional[str], optional): Web search results. Defaults to None.
#         model (str, optional): LLM model for the task. Defaults to LLM_UTILITY_2.

#     Raises:
#         ValidationError: If the LLM returns no data or missing key fields.
#         ValidationError: If contract context ingestion map is missing.
#         LLMError: On unexpected failures calling the LLM or parsing.
#     """
#     try:

#         prompt = _prompt_builder.build_context_ingestion_prompt(
#             summary=summary,
#             docs=docs,
#             invariants=invariants,
#             web_search_results=web_search_results,
#             flattened_contracts=contracts_chunk,
#         )
#         messages = _prompt_builder.build_messages(
#             model_type=model,
#             user_input=prompt,
#             system_prompt=INGESTION_SYSTEM_PROMPT,
#         )
#         llm_response = await send_prompt_to_llm_async(
#             model_type=model,
#             messages=messages,
#             response_model=ContextIngestionResponse,
#         )

#         # Validate minimal contract-level data is present
#         if not llm_response or not isinstance(llm_response, ContextIngestionResponse):
#             logger.warning("[Context Ingestion] LLM response was empty or invalid")
#             raise ValidationError(
#                 message="Invalid LLM response for context ingestion",
#                 details={"error": "Response was empty or wrong type"},
#             )

#         if not llm_response.analyzed_contracts:
#             logger.warning("[Context Ingestion] No contracts extracted from LLM response")
#             raise ValidationError(
#                 message="Context ingestion produced no contract ingestion map",
#                 details={"error": "analyzed_contracts is empty"},
#             )

#         return llm_response

#     except (LLMError, ValidationError):
#         raise
#     except Exception as e:
#         logger.exception(f"[Context Ingestion] Unexpected error in generate_context_summary: {e}")
#         raise LLMError(
#             message="Unexpected error during context ingestion",
#             details={"error": str(e)},
#         ) from e


# @observe(name="[Context Ingestion] Generate structured context")
# async def generate_context_ingestion(
#     contracts: str,
#     summary: Optional[str],
#     docs: Optional[str],
#     invariants: Optional[InvariantsResponse],
#     web_search_results: Optional[str] = None,
#     model: str = LLM_UTILITY_2,
# ) -> ContextIngestionResponse:
#     """
#     Break the full set of flattened contracts into batches, send each batch
#     to the LLM for context ingestion, merge results, and return a single
#     ContextIngestionResponse object covering all contracts.
#     """
#     logger.info("[Context Ingestion] starting – chunk size %d", CHUNK_SIZE)

#     chunks = _split_flattened_contracts(contracts, CHUNK_SIZE)
#     logger.info("[Context Ingestion] Created %d contract chunks", len(chunks))

#     merged_response: Optional[ContextIngestionResponse] = None
#     for batch_index, contracts_chunk in enumerate(chunks, start=1):
#         logger.info("[Context Ingestion] Processing batch %d/%d", batch_index, len(chunks))
#         chunk_response = await ingest_contract_chunk(
#             contracts_chunk=contracts_chunk,
#             summary=summary,
#             docs=docs,
#             invariants=invariants,
#             web_search_results=web_search_results,
#             model=model,
#         )
#         logger.info(
#             "[Context Ingestion] Batch %d complete: %d contracts processed",
#             batch_index,
#             len(chunk_response.analyzed_contracts),
#         )
#         merged_response = merge_contract_analysis(merged_response, chunk_response)
#         gc.collect()

#     total_contracts = len(merged_response.analyzed_contracts)
#     logger.info(
#         "[Context Ingestion] Completed ingestion – total %d contracts",
#         total_contracts,
#     )

#     if total_contracts == 0:
#         raise ValidationError("Context ingestion produced zero contracts after merging", details={})

#     return merged_response


#-------------------org message history-----------------------------
# import asyncio
# import gc
# import time
# from typing import Dict, List, Optional

# from langfuse.decorators import observe

# from api.v1.detectors.ingested_context_scan.schema import IngestedContextScanResponse
# from config.prompts.ingested_context_scan_prompts import (
#     INGESTED_CONTEXT_SCAN_INPUT,
#     INGESTED_CONTEXT_SCAN_SYSTEM_PROMPT,
# )
# from config.settings import LLM_SCAN_3, SUPPORTED_MODELS
# from core.llm.prompt_builder import PromptBuilder
# from core.llm.send_prompt_to_llm import send_prompt_to_llm_async
# from core.schemas.llm_schema import Message
# from core.utils.logger import logger
# from core.utils.profiles import Profiles
# from core.utils.retry_helper import retry_async_operation

# # Singleton prompt builder
# _prompt_builder = PromptBuilder()


# @observe(name="[Detector] Run ingested context scan (ICS)")
# async def run_ingested_context_scan(
#     flattened_contracts: str,
#     context_ingestion_json: str,
#     profile: Profiles = Profiles.NONE,
#     model: str = LLM_SCAN_3,
# ) -> IngestedContextScanResponse:
#     """
#     Run an ingested-context scan to detect vulnerabilities using the
#     structured context from Context Ingestion.

#     Args:
#         flattened_contracts (str): The flattened Solidity code to audit
#         context_ingestion_json (str): JSON result from the Context Ingestion phase
#         profile (Profiles, optional): The profile to use for the scan.
#         model (str, optional): The LLM model to use.

#     Returns:
#         IngestedContextScanResponse with detected issues, or an empty list if the scan failed.
#     """
#     try:
#         # 1) Build system_prompt
#         instruct_context_block = (
#             INGESTED_CONTEXT_SCAN_SYSTEM_PROMPT.strip()
#             + "\n\nContextSummaryOutput:\n```json\n"
#             + context_ingestion_json
#             + "\n```"
#         )

#         sources_block = INGESTED_CONTEXT_SCAN_INPUT.format(
#             flattened_contracts=flattened_contracts
#         ).strip()

#         is_claude = model in SUPPORTED_MODELS["anthropic"]

#         thinking = (
#             model.startswith("o1")
#             or model.startswith("o3")
#             or model.startswith("o4")
#             or model.startswith("grok-3-mini")
#             or model.startswith("claude-3-7")
#         )
        
#         messages = _prompt_builder.build_messages(
#             model_type=model,
#             user_input=sources_block,
#             system_prompt=instruct_context_block,
#             profile=profile,
#         )
        
#         # 4) Call the LLM
#         start = time.time()

#         llm_response: Optional[IngestedContextScanResponse] = await retry_async_operation(
#             send_prompt_to_llm_async,
#             model_type=model,
#             messages=messages,
#             response_model=IngestedContextScanResponse,
#             thinking=thinking,
#             system_prompt=instruct_context_block if is_claude else None,
#         )
#         elapsed = time.time() - start

#         # 4) Validate & return
#         if not llm_response or not isinstance(llm_response, IngestedContextScanResponse):
#             logger.error("[ICS] LLM response was empty or invalid")
#             return IngestedContextScanResponse(findings=[])

#         logger.debug(
#             f"[ICS] Completed for {model} "
#             f"– {len(llm_response.findings)} findings in {elapsed:.2f}s"
#         )
#         return llm_response

#     except Exception as e:
#         logger.error(f"[ICS] Failed for model {model}: {e}", exc_info=True)
#         return IngestedContextScanResponse(findings=[])


# async def run_ingested_context_scan_batch(
#     flattened_contracts: str,
#     context_ingestion_json: str,
#     batch_configs: List[Dict],
# ) -> List[IngestedContextScanResponse]:
#     """
#     Run multiple ingested-context scans in parallel, one per (profile, model).
#     Returns a list of IngestedContextScanResponse objects.
#     """
#     tasks = []
#     try:
#         for cfg in batch_configs:
#             tasks.append(
#                 run_ingested_context_scan(
#                     flattened_contracts=flattened_contracts,
#                     context_ingestion_json=context_ingestion_json,
#                     profile=cfg["profile"],
#                     model=cfg["model"],
#                 )
#             )
#         results = await asyncio.gather(*tasks, return_exceptions=True)
#         return [
#             res if not isinstance(res, Exception) else IngestedContextScanResponse(findings=[])
#             for res in results
#         ]
#     finally:
#         # Clean up large data references to free memory
#         gc.collect()
#         tasks.clear()
#         flattened_contracts = None
#         context_ingestion_json = None



#-------------------fixed custom history-----------------------------
# import asyncio
# import gc
# import time
# from typing import Dict, List, Optional

# from langfuse.decorators import observe

# from api.v1.detectors.ingested_context_scan.schema import IngestedContextScanResponse
# from config.prompts.ingested_context_scan_prompts import (
#     INGESTED_CONTEXT_SCAN_INPUT,
#     INGESTED_CONTEXT_SCAN_SYSTEM_PROMPT,
# )
# from config.settings import LLM_SCAN_3, SUPPORTED_MODELS
# from core.llm.prompt_builder import PromptBuilder
# from core.llm.send_prompt_to_llm import send_prompt_to_llm_async
# from core.schemas.llm_schema import Message
# from core.utils.logger import logger
# from core.utils.profiles import Profiles
# from core.utils.retry_helper import retry_async_operation

# # Singleton prompt builder
# _prompt_builder = PromptBuilder()


# @observe(name="[Detector] Run ingested context scan (ICS)")
# async def run_ingested_context_scan(
#     flattened_contracts: str,
#     context_ingestion_json: str,
#     profile: Profiles = Profiles.NONE,
#     model: str = LLM_SCAN_3,
# ) -> IngestedContextScanResponse:
#     """
#     Run an ingested-context scan to detect vulnerabilities using the
#     structured context from Context Ingestion.

#     Args:
#         flattened_contracts (str): The flattened Solidity code to audit
#         context_ingestion_json (str): JSON result from the Context Ingestion phase
#         profile (Profiles, optional): The profile to use for the scan.
#         model (str, optional): The LLM model to use.

#     Returns:
#         IngestedContextScanResponse with detected issues, or an empty list if the scan failed.
#     """
#     try:
#         # 1) Build system_prompt
#         instruct_context_block = (
#             INGESTED_CONTEXT_SCAN_SYSTEM_PROMPT.strip()
#             + "\n\nContextSummaryOutput:\n```json\n"
#             + context_ingestion_json
#             + "\n```"
#         )

#         sources_block = INGESTED_CONTEXT_SCAN_INPUT.format(
#             flattened_contracts=flattened_contracts
#         ).strip()

#         is_openai = model in SUPPORTED_MODELS["openai"]
#         is_claude = model in SUPPORTED_MODELS["anthropic"]

#         thinking = (
#             model.startswith("o1")
#             or model.startswith("o3")
#             or model.startswith("o4")
#             or model.startswith("grok-3-mini")
#             or model.startswith("claude-3-7")
#         )

#         messages: List[Message] = _prompt_builder.get_profile_history(profile)

#         if is_openai:
#             messages.append({"role": "system", "content": instruct_context_block})
#             messages.append({"role": "user", "content": sources_block})

#         elif is_claude:
#             combined_user = f"{instruct_context_block}\n\n{sources_block}"
#             messages.append({"role": "user", "content": combined_user})

#             # Anthropic requires cache-control objects in profile examples:
#             if profile != Profiles.NONE:
#                 messages = _prompt_builder._add_cache_control_to_messages(messages)

#         # 4) Call the LLM
#         start = time.time()

#         llm_response: Optional[IngestedContextScanResponse] = await retry_async_operation(
#             send_prompt_to_llm_async,
#             model_type=model,
#             messages=messages,
#             response_model=IngestedContextScanResponse,
#             thinking=thinking,
#             # system_prompt=instruct_context_block if is_claude else None,
#         )
#         elapsed = time.time() - start

#         # 4) Validate & return
#         if not llm_response or not isinstance(llm_response, IngestedContextScanResponse):
#             logger.error("[ICS] LLM response was empty or invalid")
#             return IngestedContextScanResponse(findings=[])

#         logger.debug(
#             f"[ICS] Completed for {model} "
#             f"– {len(llm_response.findings)} findings in {elapsed:.2f}s"
#         )
#         return llm_response

#     except Exception as e:
#         logger.error(f"[ICS] Failed for model {model}: {e}", exc_info=True)
#         return IngestedContextScanResponse(findings=[])


# async def run_ingested_context_scan_batch(
#     flattened_contracts: str,
#     context_ingestion_json: str,
#     batch_configs: List[Dict],
# ) -> List[IngestedContextScanResponse]:
#     """
#     Run multiple ingested-context scans in parallel, one per (profile, model).
#     Returns a list of IngestedContextScanResponse objects.
#     """
#     tasks = []
#     try:
#         for cfg in batch_configs:
#             tasks.append(
#                 run_ingested_context_scan(
#                     flattened_contracts=flattened_contracts,
#                     context_ingestion_json=context_ingestion_json,
#                     profile=cfg["profile"],
#                     model=cfg["model"],
#                 )
#             )
#         results = await asyncio.gather(*tasks, return_exceptions=True)
#         return [
#             res if not isinstance(res, Exception) else IngestedContextScanResponse(findings=[])
#             for res in results
#         ]
#     finally:
#         # Clean up large data references to free memory
#         gc.collect()
#         tasks.clear()
#         flattened_contracts = None
#         context_ingestion_json = None

# -----------------------------------Validation Phase ------------------------------------------------------

# class ValidationCriticPhaseRequest(BaseModel):
#     """
#     Request model for finding validation critic phase.
#     scan_id : UUID
#         The ID of the scan whose findings you want to re-validate.
#     """

#     scan_id: UUID = Field(..., description="The scan_id stored in the database")


# @router.post(
#     "/test-validation-critic-phase",
#     response_model=Union[SuccessResponse[CriticResponse], ErrorResponse],
#     description="Removes false positive findings based on predefined confidence values from a list of security findings.",
# )
# async def test_critic_phase_validation(request: ValidationCriticPhaseRequest):
#     scan = await ScanRepository.get_scan(request.scan_id)
#     full_result = await ScanRepository.get_scan_result(request.scan_id)

#     repository_url = scan.repositoryURL
#     contracts = scan.contractFiles

#     findings = full_result.findings_before_removal
#     for f in findings:
#         f.Mitigation = None
#         f.CounterArgument = None
#         f.Justification = None

#     logger.info(f"[Validation Critics Test] {findings}")

#     import os
#     import tempfile

#     tmp_dir = tempfile.mkdtemp()
#     try:
#         repo_dir = await clone_repo(
#             repository_url, tmp_dir, "test_access_token", branch=scan.branchName
#         )
#     except (AuthError, BranchError, CloneError) as e:
#         raise HTTPException(status_code=500, detail=e.message)

#     # Build contract contents mapping
#     contract_contents: Dict[str, str] = {}
#     for contract_path in contracts:
#         file_path = os.path.join(repo_dir, contract_path)
#         try:
#             with open(file_path, "r", encoding="utf-8") as f:
#                 contract_contents[contract_path] = f.read()
#         except Exception:
#             contract_contents[contract_path] = ""

#     # Execute full critic phase
#     findings = await CriticService.run_validation(
#         findings=findings,
#         contract_contents=contract_contents,
#     )

#     return SuccessResponse(
#         data=CriticResponse(
#             original_count=len(findings),
#             findings_count=len(findings),
#             findings=findings,
#         )
#     )
