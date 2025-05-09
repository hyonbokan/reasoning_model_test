from typing import Dict, List

from api.v1.scanner.benchmark.schema import BenchmarkScanContext
from config.settings import LLM_SCAN_2, LLM_SCAN_3
from core.models.user import SubscriptionType
from core.scanners.base_task_manager import BaseTaskManager
from core.schemas.context_protocols import BenchmarkContext
from core.schemas.scan_schema import Detectors, Features, ModeType, TypeOfScan
from core.utils.errors import UnsupportedOperationError
from core.utils.profiles import Profiles

from core.utils.logger import logger

class BenchmarkTaskManager(BaseTaskManager):
    """Benchmark-specific task management logic."""

    def __init__(self, context: BenchmarkScanContext):
        super().__init__(context)
        self.is_free = context.subscription_plan == SubscriptionType.FREE
        self.is_pro = context.subscription_plan == SubscriptionType.PRO
        self.is_enterprise = context.subscription_plan == SubscriptionType.ENTERPRISE
        
        # Log subscription plan and feature set
        logger.info(f"[BenchmarkTaskManager] Subscription plan: {context.subscription_plan}")
        logger.info(f"[BenchmarkTaskManager] Available features: {self.available_features}")
        logger.info(f"[BenchmarkTaskManager] Available detectors: {self.available_detectors}")

    @property
    def available_detectors(self) -> Dict[str, bool]:
        """Define available detectors for Benchmark scan."""
        if not isinstance(self.context, BenchmarkContext):
            raise UnsupportedOperationError(
                f"Context type {type(self.context).__name__} does not support Benchmark operations"
            )

        is_full_scan = self.context.type_of_scan == TypeOfScan.AUDIT_AGENT

        return {
            # Detectors.CONTEXT_SCAN.value: True,
            # Detectors.STATIC_ANALYZER.value: is_full_scan,  # Only run static analyzer for full scan
            # Detectors.FUZZER.value: False,
            # Detectors.MULTI_AGENTS.value: is_full_scan and self.is_enterprise,  # Only Enterprise
            # Detectors.SPECIALIZED_AGENTS.value: is_full_scan and not self.is_free,
            
            Detectors.CONTEXT_SCAN.value: False,
            Detectors.STATIC_ANALYZER.value: False,  # Only run static analyzer for full scan
            Detectors.FUZZER.value: False,
            Detectors.MULTI_AGENTS.value: False,  # Only Enterprise
            Detectors.SPECIALIZED_AGENTS.value: False,
        }

    @property
    def available_features(self) -> Dict[str, bool]:
        """Define available features for Benchmark scan."""
        if not isinstance(self.context, BenchmarkContext):
            raise UnsupportedOperationError(
                f"Context type {type(self.context).__name__} does not support Benchmark operations"
            )

        is_full_scan = self.context.type_of_scan == TypeOfScan.AUDIT_AGENT

        # return {
        #     Features.CUSTOM_LINKS.value: False,
        #     Features.INVARIANTS.value: is_full_scan,
        #     Features.AST_TREE.value: is_full_scan and self.is_enterprise,
        #     Features.WEB_SEARCH.value: is_full_scan and not self.is_free,
        #     Features.MITIGATION.value: is_full_scan,
        #     Features.VALIDATION.value: is_full_scan and not self.is_free,
        #     Features.CONTEXT_INGESTION.value: is_full_scan and not self.is_free,
        # }
        

        features = {
            Features.CUSTOM_LINKS.value: False,
            Features.INVARIANTS.value: is_full_scan,
            Features.AST_TREE.value: is_full_scan and self.is_enterprise,
            Features.WEB_SEARCH.value: is_full_scan and not self.is_free,
            Features.MITIGATION.value: is_full_scan,
            Features.VALIDATION.value: is_full_scan and not self.is_free,
            Features.CONTEXT_INGESTION.value: is_full_scan and not self.is_free,
        }

        logger.debug(f"[BenchmarkTaskManager] available_features: {features}")
        return features
    
    @property
    def context_scan_models(self) -> List[str]:
        if not isinstance(self.context, BenchmarkContext):
            raise UnsupportedOperationError(
                f"Context type {type(self.context).__name__} does not support Benchmark operations"
            )

        # For MODEL scan type
        if self.context.type_of_scan == TypeOfScan.MODEL:
            if self.context.mode == ModeType.VANILLA:
                return [self.context.model, self.context.model]  # 2 models for VANILLA

            return [self.context.model]  # 1 model for FEW_SHOTS

        # For AUDIT_AGENT scan type
        if self.is_free:
            return [LLM_SCAN_2, LLM_SCAN_3, LLM_SCAN_3]  # Remove o3 model for Free

        return super().context_scan_models

    @property
    def context_scan_profiles(self) -> List[Profiles]:
        if not isinstance(self.context, BenchmarkContext):
            return super().context_scan_profiles

        # For MODEL scan type
        if self.context.type_of_scan == TypeOfScan.MODEL:
            if self.context.mode == ModeType.VANILLA:
                return [Profiles.NONE]  # 1 profile for VANILLA mode

        # For AUDIT_AGENT scan type
        if self.is_free:
            return [Profiles.DEFAULT, Profiles.NONE]  # Remove 1 few-shots batch for Free
        return super().context_scan_profiles

    @property
    def context_scan_batch_size(self) -> int:
        """
        Customize batch size based on scan type.
        For model benchmarking, use smaller batches to avoid rate limits.
        """
        if not isinstance(self.context, BenchmarkContext):
            return super().context_scan_batch_size

        # For model benchmarking, use batch size of 2
        if self.context.type_of_scan == TypeOfScan.MODEL:
            return 2  # Run identical configurations in the same batch

        # For full scans, use standard batch size
        return super().context_scan_batch_size


# BaseTaskManager batch size to 1
    @final
    async def _run_ingested_context_scans(self) -> None:
        """Run ingested‐context scans in a single batch for quick testing."""
        # 1. Only zero-shot profile for test
        all_configs = self.ingested_context_scan_configs or []
        configs = [c for c in all_configs if c["profile"] == Profiles.NONE]

        total = len(configs)
        if total == 0:
            return

        # 2. One big batch
        logger.info(f"[TaskManager] Running 1 ingested‐context scan batch (zero-shot only)")
        await self._run_ingested_context_scan_batch(configs)

        # 3. Throttle
        await asyncio.sleep(1)


import asyncio
import gc
import itertools
import json
from abc import ABC, abstractmethod
from typing import Dict, List, Optional, OrderedDict, final

from api.v1.detectors.context_scan.service import run_context_scan_batch
from api.v1.detectors.fuzzer.service import FuzzerService
from api.v1.detectors.multi_agents.service import run_multi_agent
from api.v1.detectors.specialized_agents.service import run_specialized_agent
from api.v1.detectors.static_analyzer.service import run_static_analyzer
from api.v1.detectors.ingested_context_scan.service import run_ingested_context_scan_batch
from api.v1.tools.service import query_and_search_service
from api.v1.utilities.ast_tree.schema import ProjectAST
from api.v1.utilities.ast_tree.service import generate_ast_for_project
from api.v1.utilities.invariants.schema import InvariantsResponse
from api.v1.utilities.invariants.service import generate_invariants
from api.v1.utilities.summary.service import generate_summary
from api.v1.utilities.context_ingestion.schema import ContextIngestionResponse
from api.v1.utilities.context_ingestion.service import generate_context_ingestion
from config.settings import LLM_SCAN_1, LLM_SCAN_2, LLM_SCAN_3, LLM_UTILITY_2, SEARCH_ENGINE
from core.db.repositories.scan import ScanRepository
from core.models.scan import Finding, Scan
from core.schemas.context_protocols import BenchmarkContext, CompilationContext
from core.schemas.scan_schema import (
    BaseScanContext,
    Detectors,
    Features,
    ScanType,
    TypeOfScan,
)
from core.utils.logger import logger
from core.utils.profiles import Profiles

TOTAL_SCAN_TIMEOUT = 1200  # 20 minutes for entire scan
CONTEXT_SCAN_BATCH_SIZE = 3  # Number of context scans per batch

# Progress stage weights
PRE_DETECTOR_WEIGHT = 25  # Setup, cloning, etc. (0-25%)
DETECTOR_WEIGHT = 55  # Detectors (25-80%)
POST_DETECTOR_WEIGHT = 20  # Result processing (80-100%)


class BaseTaskManager(ABC):
    """Base class for all task managers with common functionality."""

    def __init__(self, context: BaseScanContext):
        self.context = context
        self.scan_id = context.scan_id
        self.scan: Optional[Scan] = None
        self.summary_result: Optional[str] = None
        self.detected_type: Optional[Profiles] = None
        self.invariants: Optional[InvariantsResponse] = None
        self.ast_tree: Optional[ProjectAST] = None
        self.web_search_results: Optional[str] = "None Given"
        self.context_ingestion_results: Optional[ContextIngestionResponse] = None
        self.task_results: Dict = {}
        self.task_detector_names: List[str] = []  # Track detector order
        self.active_detectors: List[str] = []  # Track enabled detectors
        self.context_scan_configs: List[Dict] = []
        self.ingested_context_scan_configs: List[Dict] = []
        self.detector_weights: Dict[str, float] = {}

    @property
    @abstractmethod
    def available_detectors(self) -> Dict[str, bool]:
        """
        Define available detectors and their default enabled state.
        Override in each scan type.
        Example:
        return {
            Detectors.CONTEXT_SCAN.value: True,
            Detectors.STATIC_ANALYZER.value: False,
            Detectors.FUZZER.value: False,
            Detectors.MULTI_AGENTS.value: False,
            Detectors.SPECIALIZED_AGENTS.value: True,
            Detectors.INGESTED_CONTEXT_SCAN.value: True,
        }
        """
        pass

    @property
    @abstractmethod
    def available_features(self) -> Dict[str, bool]:
        """
        Define available features and their default enabled state.
        Override in each scan type.
        Example:
        return {
            Features.CUSTOM_LINKS.value: True,
            Features.INVARIANTS.value: True,
            Features.AST_TREE.value: True,
            Features.WEB_SEARCH.value: True,
            Features.MITIGATION.value: True,
            Features.VALIDATION.value: True,
            Features.CONTEXT_INGESTION.value: True,
        }
        """
        return {
            Features.CUSTOM_LINKS.value: True,
            Features.INVARIANTS.value: True,
            Features.AST_TREE.value: True,
            Features.WEB_SEARCH.value: True,
            Features.MITIGATION.value: True,
            Features.VALIDATION.value: True,
            Features.CONTEXT_INGESTION.value: True,
        }

    @property
    def context_scan_models(self) -> List[str]:
        """
        Define the LLM models to use for context scanning.
        Can be overridden by child classes to customize model selection.
        Returns a list of model identifiers.
        """
        return [LLM_SCAN_1, LLM_SCAN_2, LLM_SCAN_3]

    @property
    def context_scan_profiles(self) -> List[Profiles]:
        """
        Define the profiles to use for context scanning.
        Can be overridden by child classes to customize profile selection.
        Returns a list of profiles.
        """
        return [Profiles.DEFAULT, Profiles.DEFAULT_2, Profiles.NONE]

    @property
    def context_scan_batch_size(self) -> int:
        """
        Define the number of context scans to run in each batch.
        Can be overridden by child classes to customize batch size.
        Returns an integer representing the batch size.
        """
        return CONTEXT_SCAN_BATCH_SIZE

    @final
    async def execute_scan(self) -> None:
        """Main scan orchestrator."""
        try:
            # 1. Initialize detectors
            await self._initialize_detectors()

            # 2. Run summary, invariants, and AST tree generation in parallel
            summary_task = asyncio.create_task(generate_summary(self.context.flattened_contracts))

            if self.available_features[Features.INVARIANTS.value]:
                invariants_task = asyncio.create_task(
                    generate_invariants(
                        contracts_in_scope=self.context.contract_files,
                        flattened_contracts=self.context.flattened_contracts,
                        docs=getattr(self.context, "formatted_docs", None),
                        selected_invariants=self.context.invariants,
                        contract_contents=self.context.contract_contents,
                    )
                )
            else:
                invariants_task = None

            # AST generation depends on setup_result existing (for project_dir)
            ast_tree_task = None
            if self.available_features[Features.AST_TREE.value]:
                if (
                    isinstance(self.context, CompilationContext)
                    and self.context.setup_result is not None
                ):
                    ast_tree_task = asyncio.create_task(
                        generate_ast_for_project(
                            repo_path=self.context.setup_result.project_dir,
                            contracts=self.context.contract_files,
                        )
                    )
            else:
                ast_tree_task = None

            # Wait for all tasks to complete
            results = await asyncio.gather(
                summary_task,
                invariants_task,
                *([] if ast_tree_task is None else [ast_tree_task]),
                return_exceptions=True,
            )

            # Process results and handle any exceptions
            # Summary task is critical
            summary_outcome = results[0]
            if isinstance(summary_outcome, Exception):
                logger.error(
                    f"[TaskManager] Critical error in summary generation: {str(summary_outcome)}"
                )
                raise summary_outcome  # Re-raise the summary exception to fail the scan
            elif summary_outcome is None:
                # This case should theoretically not happen if summary_task is always created
                error_msg = "[TaskManager] Critical error: Summary task result is None."
                logger.error(error_msg)
                raise ValueError(error_msg)
            else:
                self.summary_result, self.detected_type = summary_outcome

            # Process invariants result
            invariants_outcome = results[1]
            if isinstance(invariants_outcome, Exception):
                logger.error(
                    f"[TaskManager] Invariants generation failed: {str(invariants_outcome)}"
                )
                self.invariants = None  # Keep default or handle as needed
            elif invariants_outcome is not None:
                self.invariants = invariants_outcome

            # Process AST tree result
            if len(results) > 2:
                ast_tree_outcome = results[2]
                if isinstance(ast_tree_outcome, Exception):
                    logger.error(
                        f"[TaskManager] AST Tree generation failed: {str(ast_tree_outcome)}"
                    )
                    self.ast_tree = None  # Keep default or handle as needed
                elif ast_tree_outcome is not None:
                    self.ast_tree = ast_tree_outcome
            else:
                # Task was not run, keep default
                self.ast_tree = None

            await ScanRepository.update_scan_progress(self.scan_id, 20)

            # 3. Run web search, if enabled
            if self.available_features[Features.WEB_SEARCH.value]:
                self.web_search_results = await query_and_search_service(
                    contracts=self.context.flattened_contracts,
                    num_queries=5,
                    docs=getattr(self.context, "formatted_docs", None),
                    ast_tree=self.ast_tree,
                    search_engine=SEARCH_ENGINE,
                )
            await ScanRepository.update_scan_progress(self.scan_id, 25)
            
            # 4. Run context ingestion
            if self.available_features[Features.CONTEXT_INGESTION.value]:
                self.context_ingestion_results = await generate_context_ingestion(
                    contracts=self.context.flattened_contracts,
                    summary=self.summary_result,
                    docs=getattr(self.context, "formatted_docs", None),
                    invariants=self.invariants,
                    web_search_results=self.web_search_results,
                    model=LLM_UTILITY_2,
                )
            await ScanRepository.update_scan_progress(self.scan_id, 30)

            # 5. Execute detectors (failures handled silently)
            await self._run_detectors()

            # Clear memory after all detectors are complete
            self.context.flattened_contracts = None
            gc.collect()

            # 6. Gather results after all tasks are complete
            return await self._gather_results()

        except Exception as e:
            logger.error(f"[TaskManager] Critical error in scan execution: {str(e)}")
            raise  # Re-raise to be handled by service

    # Initialize detectors

    @final
    async def _initialize_detectors(self, **kwargs) -> None:
        """Initialize scan and configure progress tracking."""
        # Fetch scan document
        self.scan = await ScanRepository.get_scan(self.scan_id)

        # Configure active detectors from available ones
        enabled_detectors = {
            name: kwargs.get(name, enabled) for name, enabled in self.available_detectors.items()
        }
        self.active_detectors = [name for name, enabled in enabled_detectors.items() if enabled]

        # Initialize detectors based on active ones
        detectors: Dict[str, bool | None] = {}
        setup_result_exists = (
            isinstance(self.context, CompilationContext) and self.context.setup_result is not None
        )
        is_compilable = setup_result_exists and self.context.setup_result.is_compilable

        for detector in self.active_detectors:
            if detector == Detectors.CONTEXT_SCAN.value:
                await self._initialize_context_scan(detectors)
            elif detector == Detectors.INGESTED_CONTEXT_SCAN.value:
                await self._initialize_ingested_context_scan(detectors)
            elif detector == Detectors.STATIC_ANALYZER.value:
                # Requires setup and compilability
                if setup_result_exists and is_compilable:
                    await self._initialize_static_analysis(detectors)
            elif detector == Detectors.FUZZER.value:
                # Requires setup and compilability
                if setup_result_exists and is_compilable:
                    await self._initialize_fuzzing(detectors)
            elif detector == Detectors.MULTI_AGENTS.value:
                # Requires setup (for repo_root/AST) but not compilability
                if setup_result_exists:
                    await self._initialize_multi_agent(detectors)
            elif detector == Detectors.SPECIALIZED_AGENTS.value:
                await self._initialize_specialized_agents(detectors)

        # Save initial detectors to scan
        self.scan.detectors = detectors
        self.scan.total_detectors = len(detectors)
        self.scan.completed_detectors = 0

        # Calculate detector weights dynamically based on active detectors
        total_weight = DETECTOR_WEIGHT  # 55% for detectors
        self.detector_weights = {}

        # Reserve fixed weights for core detectors if they're active
        reserved_weights = {
            Detectors.STATIC_ANALYZER.value: 5,
            Detectors.FUZZER.value: 5,
            Detectors.MULTI_AGENTS.value: 25,
            Detectors.SPECIALIZED_AGENTS.value: 5,
        }

        # Calculate how much weight is reserved for ACTIVE core detectors
        total_reserved = sum(
            weight for detector, weight in reserved_weights.items() if detector in detectors
        )

        # Calculate remaining weight for context scans
        remaining_weight = total_weight - total_reserved
        context_scan_count = sum(
            1 for d in detectors if d.startswith(f"{Detectors.CONTEXT_SCAN.value}_")
        )
        
        ingested_context_scan_count = sum(
            1 for d in detectors if d.startswith(f"{Detectors.INGESTED_CONTEXT_SCAN.value}_")
        )

        # Assign weights
        for detector in detectors:
            if detector in reserved_weights:
                # Core detectors get their fixed weights
                self.detector_weights[detector] = reserved_weights[detector]
            elif detector.startswith(f"{Detectors.CONTEXT_SCAN.value}_") and context_scan_count > 0:
                # Each context scan gets an equal share of remaining weight, rounded to 1 decimal
                context_scan_weight = round(remaining_weight / context_scan_count, 1)
                self.detector_weights[detector] = context_scan_weight
            elif detector.startswith(f"{Detectors.INGESTED_CONTEXT_SCAN.value}_") and ingested_context_scan_count > 0:
                self.detector_weights[detector] = round(remaining_weight / (context_scan_count + ingested_context_scan_count), 1)

        await self.scan.save()

        logger.info(
            f"[TaskManager] Scan {self.scan_id} initialized with {len(detectors)} detectors. "
        )

    @final
    async def _initialize_context_scan(self, detectors: Dict) -> None:
        """Initialize context scan detector with LLM models, ensuring unique keys."""
        profiles = self.context_scan_profiles
        models = self.context_scan_models
        self.context_scan_configs = []  # Reset configs for this scan

        idx = 0
        for profile, model in itertools.product(profiles, models):
            # Generate a base name including profile and model
            base_detector_name = f"{Detectors.CONTEXT_SCAN.value}_{profile.value}_{model}"
            # Create a unique key by appending the index
            unique_detector_key = f"{base_detector_name}_{idx}"

            detectors[unique_detector_key] = None  # Use the unique key for tracking
            self.context_scan_configs.append(
                {
                    "detector_name": unique_detector_key,  # Store the unique key
                    "profile": profile,
                    "model": model,
                }
            )
            idx += 1
            
    @final
    async def _initialize_ingested_context_scan(self, detectors: Dict) -> None:
        """Initialize ingested context scan detector with LLM models"""
        profiles = self.context_scan_profiles
        models = self.context_scan_models
        self.ingested_context_scan_configs = []  # Reset configs for this scan

        idx = 0
        for profile, model in itertools.product(profiles, models):
            # Generate a base name including profile and model
            base_detector_name = f"{Detectors.INGESTED_CONTEXT_SCAN.value}_{profile.value}_{model}"
            # Create a unique key by appending the index
            unique_detector_key = f"{base_detector_name}_{idx}"

            detectors[unique_detector_key] = None  # Use the unique key for tracking
            self.ingested_context_scan_configs.append(
                {
                    "detector_name": unique_detector_key,  # Store the unique key
                    "profile": profile,
                    "model": model,
                }
            )
            idx += 1
            
    @final
    async def _initialize_static_analysis(self, detectors: Dict) -> None:
        """Initialize static analysis detector."""
        detectors[Detectors.STATIC_ANALYZER.value] = None

    @final
    async def _initialize_fuzzing(self, detectors: Dict) -> None:
        """Initialize fuzzing detector."""
        detectors[Detectors.FUZZER.value] = None

    @final
    async def _initialize_multi_agent(self, detectors: Dict) -> None:
        """Initialize multi-agent detector."""
        detectors[Detectors.MULTI_AGENTS.value] = None

    @final
    async def _initialize_specialized_agents(self, detectors: Dict) -> None:
        """Initialize specialized agents detector."""
        detectors[Detectors.SPECIALIZED_AGENTS.value] = None

    # Run detectors

    @final
    async def _run_detectors(self) -> None:
        """Execute detectors in a semi-sequential order with controlled parallelism."""
        try:
            # Run detectors in parallel if they don't have dependencies
            detector_tasks = []

            # Static Analysis, Fuzzing, and Multi-Agents can run in parallel
            if Detectors.STATIC_ANALYZER.value in self.active_detectors:
                task = asyncio.create_task(self._run_static_analysis())
                detector_tasks.append(task)

            if Detectors.FUZZER.value in self.active_detectors:
                task = asyncio.create_task(self._run_fuzzing())
                detector_tasks.append(task)

            if Detectors.MULTI_AGENTS.value in self.active_detectors:
                task = asyncio.create_task(self._run_multi_agent())
                detector_tasks.append(task)

            if Detectors.SPECIALIZED_AGENTS.value in self.active_detectors:
                task = asyncio.create_task(self._run_specialized_agents())
                detector_tasks.append(task)

            # Wait for parallel detectors to complete
            if detector_tasks:
                await asyncio.gather(*detector_tasks, return_exceptions=True)

            # Run context scans last (they need summary but not other results)
            if Detectors.CONTEXT_SCAN.value in self.active_detectors:
                await self._run_context_scans()
            
            if (
                Detectors.INGESTED_CONTEXT_SCAN.value in self.active_detectors
                and self.context_ingestion_results  # make sure we have context ingestion results
            ):
                await self._run_ingested_context_scans()
                
        except Exception as e:
            logger.error(f"[TaskManager] Error in detector execution: {str(e)}")

    @final
    async def _run_static_analysis(self) -> None:
        """Run static analysis if setup is available and compilable."""
        # Check for setup result AND compilability
        if (
            not isinstance(self.context, CompilationContext)
            or not self.context.setup_result
            or not self.context.setup_result.is_compilable
        ):
            if Detectors.STATIC_ANALYZER.value in self.scan.detectors:
                await self._update_progress(Detectors.STATIC_ANALYZER.value, False)
            return

        try:
            result = await run_static_analyzer(
                github_url="",
                oauth_token="",
                selected_contracts=self.context.contract_files,
                setup_result=self.context.setup_result,
            )
            self.task_results[Detectors.STATIC_ANALYZER.value] = result
            await self._update_progress(Detectors.STATIC_ANALYZER.value, True)
        except Exception as e:
            logger.error(f"[TaskManager] Static analysis failed: {str(e)}")
            self.task_results[Detectors.STATIC_ANALYZER.value] = e
            await self._update_progress(Detectors.STATIC_ANALYZER.value, False)

    @final
    async def _run_fuzzing(self) -> None:
        """Run fuzzing if setup is available and compilable."""
        # Check for setup result AND compilability
        if (
            not isinstance(self.context, CompilationContext)
            or not self.context.setup_result
            or not self.context.setup_result.is_compilable
        ):
            if Detectors.FUZZER.value in self.scan.detectors:
                await self._update_progress(Detectors.FUZZER.value, False)
            return

        try:
            result = await FuzzerService.run_fuzzer(
                github_url="",
                oauth_token="",
                selected_contracts=self.context.contract_files,
                flattened_contracts=self.context.flattened_contracts,
                setup_result=self.context.setup_result,
            )
            self.task_results[Detectors.FUZZER.value] = result
            await self._update_progress(Detectors.FUZZER.value, True)
        except Exception as e:
            logger.error(f"[TaskManager] Fuzzing failed: {str(e)}")
            self.task_results[Detectors.FUZZER.value] = e
            await self._update_progress(Detectors.FUZZER.value, False)

    @final
    async def _run_multi_agent(self) -> None:
        """Run multi-agent analysis."""
        # Requires AST (implies setup_result exists) and setup_result for repo_root
        if not self.ast_tree or not self.context.setup_result:
            if Detectors.MULTI_AGENTS.value in self.scan.detectors:
                await self._update_progress(Detectors.MULTI_AGENTS.value, False)
            return

        try:
            result = await run_multi_agent(
                contracts_in_scope=self.context.contract_files,
                ast_tree=self.ast_tree,
                project_dir=self.context.setup_result.repo_root,
                docs=getattr(self.context, "formatted_docs", None),
            )
            self.task_results[Detectors.MULTI_AGENTS.value] = result
            await self._update_progress(Detectors.MULTI_AGENTS.value, True)
        except Exception as e:
            logger.error(f"[TaskManager] Multi-agents analysis failed: {str(e)}")
            self.task_results[Detectors.MULTI_AGENTS.value] = e
            if Detectors.MULTI_AGENTS.value in self.scan.detectors:
                await self._update_progress(Detectors.MULTI_AGENTS.value, False)

    @final
    async def _run_specialized_agents(self) -> None:
        """Run specialized agent analysis."""
        if Detectors.SPECIALIZED_AGENTS.value not in self.active_detectors:
            return

        try:
            result = await run_specialized_agent(
                flattened_contracts=self.context.flattened_contracts,
            )
            self.task_results[Detectors.SPECIALIZED_AGENTS.value] = result
            await self._update_progress(Detectors.SPECIALIZED_AGENTS.value, True)
        except Exception as e:
            logger.error(f"[TaskManager] Specialized agent(s) failed: {str(e)}")
            if Detectors.SPECIALIZED_AGENTS.value in self.scan.detectors:
                await self._update_progress(Detectors.SPECIALIZED_AGENTS.value, False)
    
    @final
    async def _run_context_scans(self) -> None:
        """Run context scans in sequential batches."""
        batch_size = self.context_scan_batch_size
        configs = self.context_scan_configs
        total_configs = len(configs)

        # Calculate how many batches we'll need
        total_batches = (total_configs + batch_size - 1) // batch_size
        logger.info(
            f"[TaskManager] Running {total_batches} context scan batches with batch size {batch_size}"
        )

        # Process all configs in batches sequentially
        for i in range(0, total_configs, batch_size):
            batch_end = min(i + batch_size, total_configs)
            batch = configs[i:batch_end]

            if batch:
                batch_num = (i // batch_size) + 1
                logger.info(
                    f"[TaskManager] Starting batch {batch_num}/{total_batches} with models: {[c['model'] for c in batch]} and profiles: {[c['profile'] for c in batch]}"
                )
                await self._run_context_scan_batch(batch)

                # Add a small delay between batches to avoid rate limits
                await asyncio.sleep(1)

    @final
    async def _run_context_scan_batch(self, batch_configs: List[Dict]) -> None:
        """Execute a batch of context scans and process results."""
        is_model_scan = False
        if (
            isinstance(self.context, BenchmarkContext)
            and self.context.type_of_scan == TypeOfScan.MODEL
        ):
            is_model_scan = True

        # Determine contract language based on scan type
        contract_language = "cairo" if self.context.scan_type == ScanType.CAIRO else "solidity"

        try:
            results = await run_context_scan_batch(
                contracts=self.context.flattened_contracts,
                summary=self.summary_result,
                docs=None if is_model_scan else getattr(self.context, "formatted_docs", None),
                invariants=None if is_model_scan else self.invariants,
                web_search_results=(
                    self.web_search_results
                    if batch_configs[0]["profile"] == Profiles.NONE
                    else None
                ),
                batch_configs=batch_configs,
                contract_language=contract_language,
            )

            # Process successful results
            if results:
                for config, result in zip(batch_configs, results):
                    detector_name = config["detector_name"]
                    self.task_results[detector_name] = result
                    self.task_detector_names.append(detector_name)
                    await self._update_progress(detector_name, True)

        except Exception as e:
            logger.error(f"[TaskManager] Batch context scan failed: {str(e)}")
            # Handle failures for all detectors in the batch
            for config in batch_configs:
                detector_name = config["detector_name"]
                self.task_results[detector_name] = e
                self.task_detector_names.append(detector_name)
                await self._update_progress(detector_name, False)

    @final
    async def _run_ingested_context_scans(self) -> None:
        """Run all ingested‐context scans in sequential batches."""
        batch_size = self.context_scan_batch_size
        configs = self.ingested_context_scan_configs
        total = len(configs)
        if total == 0:
            return

        total_batches = (total + batch_size - 1) // batch_size
        logger.info(f"[TaskManager] Running {total_batches} ingested‐context scan batches")
        
        # Accumulator for all previous findings
        all_findings: List[Finding] = []

        for idx in range(0, total, batch_size):
            batch = configs[idx : idx + batch_size]
            batch_num = (idx // batch_size) + 1
            logger.info(
                f"[TaskManager] ICS batch {batch_num}/{total_batches} "
                f"models={[c['model'] for c in batch]} profiles={[c['profile'] for c in batch]}"
            )
            
            # prepare previous findings or None if first pass
            prev_findings_json = (
                json.dumps([finding.model_dump(mode="json") for finding in all_findings], ensure_ascii=False)
                if all_findings
                else None
            )
            
            results = await self._run_ingested_context_scan_batch(
                batch_configs=batch,
                previous_findings_json=prev_findings_json,
            )
            
            # Accumulate new, unique findings for next round
            for res in results:
                for finding in res.findings:
                    if finding not in all_findings:
                        all_findings.append(finding)
                        
            # throttle to avoid rate‐limits
            await asyncio.sleep(1)


    @final
    async def _run_ingested_context_scan_batch(
        self, 
        batch_configs: List[Dict],
        previous_findings_json: Optional[str] = None,
        ) -> None:
        """
        Execute one batch of ingested-context scans and process results.
        Mirrors the structure of _run_context_scan_batch.
        """
        # call the batch service
        results = await run_ingested_context_scan_batch(
            flattened_contracts=self.context.flattened_contracts,
            context_ingestion_json=self.context_ingestion_results.model_dump_json(),
            batch_configs=batch_configs,
            previous_findings_json=previous_findings_json,
        )

        # iterate and record
        for cfg, res in zip(batch_configs, results):
            detector_name = cfg["detector_name"]
            self.task_results[detector_name] = res
            self.task_detector_names.append(detector_name)
            await self._update_progress(detector_name, True)
        
        return results
            
    # Gather results | Update progress | Cleanup running tasks

    @final
    async def _gather_results(self) -> None:
        """Gather and process results from all detectors."""
        combined_findings: List[Finding] = []
        findings_by_detector = {}

        # Process context scan results in order they were received
        for detector_name in self.task_detector_names:
            result = self.task_results.get(detector_name)

            if not isinstance(result, (Exception, asyncio.TimeoutError)):
                findings = result.findings
                for finding in findings:
                    finding.Detector = detector_name
                findings_by_detector[detector_name] = findings
                combined_findings.extend(findings)
            else:
                findings_by_detector[detector_name] = []
                logger.error(f"Context scan failed - Detector: {detector_name}")

        # Process static analysis results
        if Detectors.STATIC_ANALYZER.value in self.task_results:
            static_result = self.task_results[Detectors.STATIC_ANALYZER.value]
            if not isinstance(static_result, Exception):
                try:
                    static_findings = static_result.findings
                    for finding in static_findings:
                        finding.Detector = Detectors.STATIC_ANALYZER.value
                    findings_by_detector[Detectors.STATIC_ANALYZER.value] = static_findings
                    combined_findings.extend(static_findings)
                except Exception as e:
                    logger.error(f"Static analysis results processing failed: {str(e)}")
                    findings_by_detector[Detectors.STATIC_ANALYZER.value] = []
            else:
                logger.error(f"Static analysis failed: {static_result}")
                findings_by_detector[Detectors.STATIC_ANALYZER.value] = []

        # Process fuzzing results
        if Detectors.FUZZER.value in self.task_results:
            fuzzing_result = self.task_results[Detectors.FUZZER.value]
            if not isinstance(fuzzing_result, Exception):
                fuzzing_findings = getattr(fuzzing_result.data, "findings", [])
                for finding in fuzzing_findings:
                    finding.Detector = Detectors.FUZZER.value
                findings_by_detector[Detectors.FUZZER.value] = fuzzing_findings
                combined_findings.extend(fuzzing_findings)
            else:
                logger.error(f"Fuzzing failed: {fuzzing_result}")
                findings_by_detector[Detectors.FUZZER.value] = []

        # Process multi-agents results
        if Detectors.MULTI_AGENTS.value in self.task_results:
            multi_agents_result = self.task_results[Detectors.MULTI_AGENTS.value]
            if not isinstance(multi_agents_result, Exception):
                multi_agents_findings = multi_agents_result.findings
                for finding in multi_agents_findings:
                    finding.Detector = Detectors.MULTI_AGENTS.value
                findings_by_detector[Detectors.MULTI_AGENTS.value] = multi_agents_findings
                combined_findings.extend(multi_agents_findings)
            else:
                logger.error(f"Multi-agents analysis failed: {multi_agents_result}")
                findings_by_detector[Detectors.MULTI_AGENTS.value] = []

        # Process specialized-agents results
        if Detectors.SPECIALIZED_AGENTS.value in self.task_results:
            specialized_agents_result = self.task_results[Detectors.SPECIALIZED_AGENTS.value]
            if not isinstance(specialized_agents_result, Exception):
                specialized_agents_findings = specialized_agents_result.findings
                for finding in specialized_agents_findings:
                    finding.Detector = Detectors.SPECIALIZED_AGENTS.value
                findings_by_detector[Detectors.SPECIALIZED_AGENTS.value] = (
                    specialized_agents_findings
                )
                combined_findings.extend(specialized_agents_findings)
            else:
                logger.error(f"Specialized agent(s) analysis failed: {specialized_agents_result}")
                findings_by_detector[Detectors.SPECIALIZED_AGENTS.value] = []

        # Update scan status in database
        if self.scan:
            await self.scan.save()

        # Use OrderedDict for duplicate removal while preserving order
        initial_length = len(combined_findings)
        combined_findings = list(OrderedDict.fromkeys(combined_findings))
        final_length = len(combined_findings)
        logger.info(
            f"[TaskManager] Initial length: {initial_length}, compression with OrderedDict {final_length}"
        )

        # Save summary, type & combined findings early
        scan_result_to_update = await ScanRepository.get_scan_result(self.scan_id)
        scan_result_to_update.summary = self.summary_result
        scan_result_to_update.findings_before_removal = (
            combined_findings  # store initial findings' list
        )
        scan_result_to_update.type = (
            self.detected_type if isinstance(self.detected_type, Profiles) else Profiles.DEFAULT
        )
        if self.invariants:
            scan_result_to_update.invariants = self.invariants.invariants or []
        else:
            scan_result_to_update.invariants = []
        await ScanRepository.store_scan_result(scan_result_to_update, is_new=False)

    @final
    async def _update_progress(self, detector_name: str, success: bool) -> None:
        """
        Update scan progress when a detector completes.

        Args:
            detector_name: Name of the detector that completed
            success: Whether the detector completed successfully
        """
        if not self.scan:
            logger.warning(
                f"[TaskManager] Cannot update progress for {detector_name}: scan not initialized"
            )
            return

        # Validate detector exists
        if detector_name not in self.detector_weights:
            logger.error(f"[TaskManager] Unknown detector {detector_name} - cannot update progress")
            return

        self.scan.completed_detectors += 1
        self.scan.detectors[detector_name] = success

        # Calculate progress as an integer percentage, up to maximum of 80%
        # This leaves room for result_processor to continue from 80% to 100%
        current_progress = PRE_DETECTOR_WEIGHT
        for name, completed in self.scan.detectors.items():
            if completed is not None:
                weight = self.detector_weights.get(name, 0)
                current_progress += weight

        # Convert to integer and scale to max 80%
        max_detector_progress = 80
        progress_int = min(int(current_progress), max_detector_progress)

        # If all initialized detectors are complete, set progress to 80%
        if self.scan.completed_detectors == self.scan.total_detectors:
            progress_int = max_detector_progress

        self.scan.progress = max(self.scan.progress, progress_int)
        await self.scan.save()

    @final
    async def _cleanup_running_tasks(self) -> None:
        """Clean up any running tasks and release resources."""
        cleanup_errors = []

        async def safe_cancel(task: asyncio.Task, task_name: str) -> None:
            """Helper function to safely cancel a task."""
            if not task or task.done():
                return

            try:
                task.cancel()
                await task
            except asyncio.CancelledError:
                # This is expected when cancelling tasks
                pass
            except Exception as e:
                error_msg = f"Error during {task_name} cleanup: {str(e)}"
                cleanup_errors.append(error_msg)
                logger.error(error_msg)

        # Track all running tasks that need cleanup
        running_tasks = []

        # Add context scan tasks if any are running
        context_scan_detectors = [
            d for d in self.active_detectors if d.startswith(f"{Detectors.CONTEXT_SCAN.value}_")
        ]
        for detector in context_scan_detectors:
            if detector in self.task_results:
                task = self.task_results[detector]
                if isinstance(task, asyncio.Task):
                    running_tasks.append((task, f"{Detectors.CONTEXT_SCAN.value}_{detector}"))
        
        # Add ingested‐context scan tasks if any are running
        ingested_scan_detectors = [
            d for d in self.active_detectors if d.startswith(f"{Detectors.INGESTED_CONTEXT_SCAN.value}_")
        ]
        for detector in ingested_scan_detectors:
            if detector in self.task_results:
                task = self.task_results[detector]
                if isinstance(task, asyncio.Task):
                    running_tasks.append((task, f"{Detectors.INGESTED_CONTEXT_SCAN.value}_{detector}"))

        # Add static analysis task if running
        if Detectors.STATIC_ANALYZER.value in self.task_results:
            task = self.task_results[Detectors.STATIC_ANALYZER.value]
            if isinstance(task, asyncio.Task):
                running_tasks.append((task, Detectors.STATIC_ANALYZER.value))

        # Add fuzzing task if running
        if Detectors.FUZZER.value in self.task_results:
            task = self.task_results[Detectors.FUZZER.value]
            if isinstance(task, asyncio.Task):
                running_tasks.append((task, Detectors.FUZZER.value))

        # Add multi-agents task if running
        if Detectors.MULTI_AGENTS.value in self.task_results:
            task = self.task_results[Detectors.MULTI_AGENTS.value]
            if isinstance(task, asyncio.Task):
                running_tasks.append((task, Detectors.MULTI_AGENTS.value))

        # Add specialized agents task if running
        if Detectors.SPECIALIZED_AGENTS.value in self.task_results:
            task = self.task_results[Detectors.SPECIALIZED_AGENTS.value]
            if isinstance(task, asyncio.Task):
                running_tasks.append((task, Detectors.SPECIALIZED_AGENTS.value))

        # Cancel all running tasks
        for task, name in running_tasks:
            await safe_cancel(task, name)

        # Log cleanup results
        if cleanup_errors:
            logger.warning(
                f"[TaskManager] Task cleanup completed with {len(cleanup_errors)} errors"
            )
            for error in cleanup_errors:
                logger.warning(error)

        # Force garbage collection after cleanup
        gc.collect()
