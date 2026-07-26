# API Contract Checklist

API changes affect every consumer — frontend, mobile, partners, internal services. Scan for changes that break contracts silently.

## What to scan for

### 1. Breaking changes without versioning
Any of these is a breaking change unless the endpoint is clearly unreleased:

- **Removing an endpoint** or HTTP method
- **Removing a response field** (consumers may depend on it)
- **Renaming a field** (same as remove + add)
- **Changing a field's type** (`string` → `number`, nullable → non-null)
- **Changing enum values** or adding required values
- **Adding a required request field** (old clients don't send it)
- **Making an optional field required**
- **Changing validation rules to be stricter** (e.g., max length reduced)
- **Changing HTTP status codes** for the same condition
- **Changing response structure** (array → object, flat → nested)

**Detection**: For each modified router/handler, diff the response/request shape against the previous version.

### 2. Silent behavior changes
Same API shape, different behavior:
- Default value changes (e.g., `limit` default from 100 → 20)
- Sort order changes
- Pagination style changes (offset → cursor without a new param)
- Error response format changes (even if status code is same)
- Timezone handling changes (UTC → local)

### 3. Request validation gaps
- Accepting types that will break downstream (e.g., accepting `"123"` as string but expecting int)
- Missing length/range limits → DoS via huge payloads
- Missing enum validation → arbitrary strings flow into business logic
- Inconsistent validation between client and server (client strict, server lax)

### 4. Response consistency
- Error responses with different shapes per endpoint (`{error: "..."}` vs `{detail: "..."}` vs `{message: "..."}`)
- Timestamps in different formats across endpoints (ISO vs epoch vs custom)
- IDs as strings in some endpoints, numbers in others
- Pagination metadata shape differs per list endpoint

### 5. Idempotency
- POST endpoints that modify state without idempotency keys
- Retry-safe operations not marked as safe
- Missing `Idempotency-Key` support on payment/order-like operations

### 6. Authentication & authorization on new endpoints
- New endpoint added without auth guard (see security-checklist)
- Different auth mechanism than peer endpoints
- Missing rate limits on expensive operations
- Admin-only operations without role checks

### 7. Pagination / filtering consistency
- New list endpoint without pagination → will break at scale
- Pagination style mismatches existing endpoints (some offset, some cursor)
- Filter parameter naming inconsistency (`q` vs `search` vs `filter`)
- Sort parameter inconsistency (`sort=-date` vs `order_by=date&dir=desc`)

### 8. OpenAPI / schema drift
If the project has OpenAPI spec or similar schema:
- Schema file not updated with code changes
- Schema says field is required, code accepts it missing
- Schema example outdated
- Schema and actual response diverge on field names

**Detection**: compare schema file modification time to router/handler changes.

### 9. Client-server contract drift (monorepo)
If frontend and backend are in the same repo:
- Backend adds a field, frontend types don't include it
- Backend removes a field, frontend still references it
- Enum values added in backend not reflected in frontend enum
- Request body shape changed on one side only

**Detection**: grep frontend for the endpoint path, check the TypeScript/JS types match.

### 10. Deprecation hygiene
- Endpoints marked `@deprecated` but no sunset date
- Deprecation warnings not logged/surfaced to clients
- Deprecated endpoints without migration guide
- Old versions kept "for safety" indefinitely

## Detection strategies

1. **List all modified routers** — for each, diff request/response shape
2. **grep for decorators/routes added** — verify auth, rate limit, validation
3. **Check OpenAPI/schema files** — modification time vs router changes
4. **grep frontend for API paths** — check types match response
5. **Look for new enum values** — every consumer must handle them

## Questions to ask

- "What version of the client will this break?"
- "Is this change additive or subtractive?"
- "Does the schema reflect this change?"
- "Would an existing client still work without code changes?"
- "Are the error responses consistent with the rest of the API?"
- "Is this endpoint authenticated the same way as its peers?"

## Output format

```markdown
## API contract findings

### P0 - Breaking changes
- `routers/trades.py:45` — removed `stockName` from response, frontend still references it
- `routers/predict.py:20` — renamed `confidence` to `conviction`, no version bump

### P1 - Auth inconsistency
- `routers/intraday.py:17` — new endpoint, no auth guard; peers use `Depends(require_api_key)`

### P1 - Schema drift
- OpenAPI spec `openapi.yaml` not updated for new `/intraday/backtest` endpoint

### P2 - Consistency
- `/intraday/backtest` returns `{total_pnl: ...}` but peers use `{totalPnl: ...}` — naming inconsistency
- New list endpoint has no pagination; peer endpoints paginate at 100
```
