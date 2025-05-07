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
        enabled = self.available_features  # triggers the property
        logger.info(f"[BenchmarkTaskManager] Enabled features: {enabled}")

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
