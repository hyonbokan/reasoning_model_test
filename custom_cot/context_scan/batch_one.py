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