# Testing Async STARK Proof Generation

## Quick Start

### 1. Start Backend (if not running via systemd)

```bash
cd /home/mlayug/Documents/projects/zkip-stark
socat TCP-LISTEN:8080,fork,reuseaddr EXEC:'lake exe Main' &
```

Or use systemd:
```bash
sudo systemctl start zkip-stark-backend.service
sudo systemctl status zkip-stark-backend.service
```

Demo-only (skip real proof generation to avoid OOM on software-only proving):
```bash
export ZKIP_DEMO_FAST_PROOF=true
```

### 2. Start Frontend

```bash
cd /home/mlayug/Documents/projects/zkiosk-frontend
npm run dev
```

Frontend will be available at: http://localhost:3000

### 3. Test Flow

1. **Open Browser**: Navigate to http://localhost:3000
2. **Use Dev Simulator**: Click the "Dev Simulator" button (top right)
3. **Trigger State Machine**:
   - Enable "Physical Link" (simulates USB connection)
   - Enable "Biometric Auth" (simulates fingerprint)
   - System will automatically transition: `idle` → `handshake` → `authorized` → `proving`
4. **Observe Async Proof Generation**:
   - **Progress Bar**: Orange bar at top will animate from 0% → 100%
   - **Polling**: Frontend polls backend every 500ms
  - **Lender Updates**: Active lender cards will update from "scanning" → "eligible"/"not-eligible"
  - **Proof Mode**: With `ZKIP_DEMO_FAST_PROOF=true`, proofs are stubbed for demo stability

### 4. What to Watch For

#### Visual Indicators:
- ✅ **Progress Bar**: Top of screen, orange, animates smoothly
- ✅ **Lender Cards**: Change colors (gray → green/red) as proofs complete
- ✅ **Console Logs**: Open browser DevTools to see polling and completion logs
- ✅ **Proof Receipt**: Appears when all 50 lenders are processed

#### Backend Logs:
```bash
# Watch backend logs
tail -f /tmp/zkip-backend.log
# Or if using systemd:
sudo journalctl -u zkip-stark-backend.service -f
```

#### Expected Timeline (demo mode):
- **0-1s**: Job created, returns 202 with jobId
- **1-5s**: Background pipeline steps (progress updates every 500ms)
- **~5s**: Job completes, lenders update, receipt appears

### 5. Verify Proof Mode

- Demo mode: `result.proof.vkId` is `"demo_no_proof"` and proof data is empty.
- Real mode: proof data is a large hex string and `vkId` matches the backend circuit.

## Manual API Testing

### Create Async Job
```bash
curl -X POST http://localhost:8080/api/v1/financing/batch-eligibility/async \
  -H "Content-Type: application/json" \
  -d '{
    "creditScore": 750,
    "income": 75000,
    "debtToIncomeRatio": 25,
    "merkleRoot": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "merkleProof": {
      "rootHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "path": [],
      "isLeft": []
    },
    "lenders": [
      {
        "lenderId": "0x4c454e44455231",
        "minIncome": 50000,
        "minCreditScore": 700,
        "maxDebtToIncome": 3000
      }
    ]
  }'
```

### Poll Job Status
```bash
# Replace {jobId} with actual jobId from above
curl http://localhost:8080/api/v1/jobs/{jobId}/status
```

## Troubleshooting

### Backend Not Responding
```bash
# Check if backend is running
curl http://localhost:8080/health

# Check systemd status
sudo systemctl status zkip-stark-backend.service

# Check logs
sudo journalctl -u zkip-stark-backend.service -n 50
```

### Frontend Not Connecting
```bash
# Check frontend is running
curl http://localhost:3000

# Check backend URL in frontend
# Should be: http://localhost:8080
```

### Progress Not Updating
- Check browser console for errors
- Verify React Query is polling (Network tab should show requests every 500ms)
- Check job status endpoint returns `progress` field

### Lenders Not Updating
- Check browser console for completion logs
- Verify `jobStatus.status === "completed"` in Network tab
- Check that `jobStatus.result` contains proof data
