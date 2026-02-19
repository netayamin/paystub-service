# Availability providers (Resy, OpenTable)

Discovery is **provider-agnostic**: buckets, drop_events, feed, just-opened, and new-drops all work on a **normalized slot shape**. Only the way we **fetch** data differs per provider.

## Interface

- **`app.services.providers.base.AvailabilityProvider`**  
  Protocol: `provider_id: str` and `search_availability(date_str, time_slot, party_sizes) -> list[NormalizedSlotResult]`.

- **`NormalizedSlotResult`**  
  One row per (venue, time): `slot_id`, `venue_id`, `venue_name`, `payload`.  
  Payload must include `availability_times`, `resy_url` or `book_url`; optional `neighborhood`, `image_url`, `price_range`, etc.

- **`slot_id(provider_id, venue_id, actual_time)`**  
  Stable 32-char hash so baseline/prev/curr diff is per provider+venue+time.

## Registered providers

| Id          | Class             | Notes |
|------------|-------------------|--------|
| `resy`     | ResyProvider      | Wraps existing Resy search_with_availability. |
| `opentable`| OpenTableProvider | OpenTable MultiSearchResults GQL (NYC). |

## Usage

- **Buckets**  
  `fetch_for_bucket(date_str, time_slot, party_sizes, provider="resy")` calls `get_provider(provider).search_availability(...)` and returns rows. Default remains `resy`; pass `provider="opentable"` to use OpenTable for that fetch.

- **API**  
  `GET /chat/providers` returns `{"providers": ["resy", "opentable"]}`.

- **Adding a provider**  
  1. Implement a class with `provider_id` and `search_availability(...)` returning `list[NormalizedSlotResult]`.  
  2. In `app.services.providers.registry` call `register("your_id", YourProvider())`.

## OpenTable

- Endpoint: `https://www.opentable.com/dapi/fe/gql?optype=query&opname=MultiSearchResults`
- Request: POST JSON with `operationName`, `variables` (date, time, partySize, lat/lon, metroId, etc.), `extensions.persistedQuery`.
- Response: `data.restaurantSearchV2.searchResults.restaurants[]`; each has `restaurantId`, `name`, `neighborhood.name`, `urls.profileLink.link`, `photos.profileV3.*`, `priceBand.name`. We map each to one slot at the requested time.
