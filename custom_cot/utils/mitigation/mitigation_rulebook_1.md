### 📑 Master Rule Book  (version 1.0)

---

#### [overflow]  Overflow / Underflow Mitigation Rules
* Compiler versions **≥ 0.8** automatically revert on overflow/underflow.  
* **Flag as a true vulnerability only if _any_ of the following is true**:  
  1. Code is wrapped in an explicit **`unchecked {}`** block.  
  2. Business requirements demand alternative handling (e.g., custom error).  
  3. The arithmetic flaw participates in a **larger exploit chain**.  
* Otherwise classify as **false positive** and recommend removal.

---

#### [reentrancy]  Re‑Entrancy Mitigation Rules
* A finding is **kept** *only if **all** of these are met*:  
  1. **No** re‑entrancy guard (`nonReentrant`, Solidity `ReentrancyGuard`, etc.).  
  2. External call targets an **untrusted** contract.  
  3. **State changes occur *after* the external call**.  
* **Mark as false positive** if **any** of the following apply:  
  – Guard present – CEI pattern respected – No post‑call state change  
  – Call is internal (same contract)

---

#### [access]  Access‑Control Mitigation Rules
* Distinguish security flaws from mere centralisation.  
* Flag **High** severity **only** if:  
  1. An un‑privileged actor can invoke a privileged function **and**  
  2. A clear exploit path exists with significant impact **and**  
  3. It contradicts declared protocol assumptions.  
* Otherwise:  
  – Centralisation risks default to **Info**.  
  – Elevate to **Medium/High** only if they break stated decentralisation goals, permit critical manipulation, or omit necessary timelocks.

---

#### [fp]  False‑Positive Identification Rules
Remove a finding entirely (`should_be_removed : true`) if **any** is true:
1. Overflow/underflow on Solidity ≥ 0.8 with **no** `unchecked` block.  
2. Re‑entrancy finding where proper guard/CEI is present.  
3. Exact or near‑duplicate of another finding.  
4. Behaviour is **documented and intentional**.  
5. Purely theoretical; no practical exploit path.

---

#### [severity]  Severity Adjustment Rules
* **Step 1 Impact**  (high / medium / low) — consequence if exploited.  
* **Step 2 Likelihood**  (high / medium / low) — probability of exploit.  
* **Step 3 Matrix**   combine as table below.  
* If torn between two severities, pick the **lower**.  
* Allowed output values: `"high"`, `"medium"`, `"low"`, `"info"`, `"best practices"`.

| Impact \\ Likelihood | **High** | **Medium** | **Low** |
|----------------------|----------|------------|---------|
| **High**             | High     | Medium     | Medium  |
| **Medium**           | High     | Medium     | Low     |
| **Low**              | Medium   | Low        | Low     |

---

#### [additional]  Response & Formatting Rules
* Output must follow the **AuditResponse** JSON schema.  
* Use lowercase field name `"severity"`.  
* Return **`index`**, adjusted `"severity"`, and optional `"comments"`.  
* **Do not** modify unrelated description/code in the finding.  
* Only set `"should_be_removed": true` when **certain** it is a false positive.  
* Be concise but clear in `"comments"`.

---

#### [final]  Final-disposition Rules
* No specific. Use checklist answer X-1 only.
---