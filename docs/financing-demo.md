# Financing Eligibility Demo

## API Endpoint

**POST** `/api/v1/financing/eligibility`

## Request Format

```json
{
  "creditScore": 750,
  "income": 75000,
  "debtToIncomeRatio": 2500,
  "lenderId": "0x0102030405060708",
  "minIncome": 50000,
  "minCreditScore": 700,
  "maxDebtToIncome": 3000,
  "thresholdLenderId": "0x0102030405060708"
}
```

### Field Descriptions

- `creditScore`: Applicant's credit score (0-850)
- `income`: Annual income in dollars
- `debtToIncomeRatio`: Debt-to-income ratio (scaled by 100, e.g., 2500 = 25%)
- `lenderId`: Lender identifier (hex string, 8+ bytes)
- `minIncome`: Minimum income threshold
- `minCreditScore`: Minimum credit score threshold
- `maxDebtToIncome`: Maximum debt-to-income ratio (scaled by 100)
- `thresholdLenderId`: Lender ID for threshold binding (must match `lenderId`)

## Response Format

### Success (Eligible)

```json
{
  "success": true,
  "eligible": true,
  "proof": {
    "vkId": "lender_eligibility_aiur_vk",
    "publicInputs": ["0x...", "0x...", "0x...", "0x..."],
    "proofData": "0x..."
  },
  "message": "Eligibility verified with zero-knowledge proof"
}
```

### Success (Not Eligible)

```json
{
  "success": true,
  "eligible": false,
  "message": "Applicant does not meet eligibility criteria"
}
```

## Example Usage

### Using curl

```bash
curl -X POST http://localhost:8080/api/v1/financing/eligibility \
  -H "Content-Type: application/json" \
  -d '{
    "creditScore": 750,
    "income": 75000,
    "debtToIncomeRatio": 2500,
    "lenderId": "0x0102030405060708",
    "minIncome": 50000,
    "minCreditScore": 700,
    "maxDebtToIncome": 3000,
    "thresholdLenderId": "0x0102030405060708"
  }'
```

## Running Tests

```bash
lake build Tests.FinancingTests
lake exe Tests.FinancingTests
```

## Security Notes

- Financial data (income, credit score, debt-to-income) remains private
- Only thresholds and lender ID are public
- Lender ID binding prevents replay attacks across different lenders
- **SECURITY VIOLATION**: In-circuit Merkle proof for financial data source not yet implemented
