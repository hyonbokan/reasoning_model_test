1. Chunking failed:
    - leads to model confusion
    - the entirity of project is not visuble 
        --> divide project and contract
        --> input all contracts, but prompt is dynamic to process contracts in chunk

2. Context Scan:
    - we may want to remove severity in CS and ICS
    
3. Custom CoT:
    - checklist Q&A is not sequential. It is likely it answers the questions all over again???
    - run 2 calls:
        1. answer the questions - y/n
        2. process the answers for the final verdict