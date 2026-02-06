# Resy booking flow (auto-book)

## What is the book token?

The **book_token** is a **slot-specific, short-lived token** that Resy issues when you "select" a specific available time. It is **not** returned by the venue search we use today. You get it from a separate API call that means "get details / reserve this slot" (often called "find" or "details").

- **Search** (what we have): `POST /3/venuesearch/search` → returns venues and which have availability, with slot times.
- **Find** (what we need): some endpoint that takes **venue_id + date + time (+ party_size, maybe config_id)** and returns a **book_token** for that slot.
- **Book**: `POST /3/book` with that **book_token** + payment method → creates the reservation.

So **yes, we can get it** — we need to call Resy’s "find" (or equivalent) endpoint for the chosen slot.

## How to discover the find endpoint

1. Log in at [resy.com](https://resy.com).
2. Open DevTools → **Network**.
3. Go to a restaurant → pick a **date** → click on an **available time** (the step right before the final "Book" button).
4. In Network, filter by `resy.com` or `api.resy.com` and look for a **POST** that happens when you click the time. That request’s URL and body are the "find" call; its **response** should contain something like `book_token` or similar.
5. Share that URL, method, and request body shape (and, if possible, a redacted response with the token field name), and we can wire `get_book_token(venue_id, date, time, ...)` and then auto-book when we have availability.

## Book endpoint (implemented)

- **URL**: `POST https://api.resy.com/3/book`
- **Body**: `application/x-www-form-urlencoded` (not JSON), e.g.:
  - `book_token` (required) — from the find step above.
  - `struct_payment_method` — JSON string, e.g. `{"id": 28157046}` (user’s payment method id from Resy).
  - `source_id=resy.com-venue-details`
  - `venue_marketing_opt_in=1`
  - `rwg_token` — may be required (capture from same Network request as book).
  - `merchant_changed=1`

**Response** (success): `reservation_id`, `resy_token`, `venue_opt_in`, etc.

Payment method id can be taken from the same Resy book request in the Network tab (`struct_payment_method` or body field that contains the payment method id).

## Auto-book in this app

Planned flow:

1. User opts in to **auto-book** for a notify request (and provides or we store payment method id).
2. When the notify job finds availability for that venue/date/party_size:
   - Call the **find** endpoint for one of the available slots (e.g. first slot or user’s preferred time) to get **book_token**.
   - Call **book** with that **book_token** and the user’s payment method.
3. Create a notification like "We booked you at Venue X for [time]. Reservation ID: …"

Until the find endpoint is known and implemented, we can still add the **option** in the UI/agent ("notify only" vs "auto-book when available") and store it; auto-book will only run once we implement the find call and have a stored payment method.
