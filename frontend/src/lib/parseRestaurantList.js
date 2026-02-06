/**
 * Parse assistant message content into a list of { name, times } for the restaurant list sidebar.
 * Expects lines like "Venue Name", "Venue Name 19:00", or "Venue Name 7:30 PM, 8:00 PM".
 * Excludes follow-up questions and non-venue lines so the sidebar shows only restaurant names.
 */

const TIME_PATTERN = /\b(\d{1,2}:\d{2})(?:\s*[AP]M)?(?:\s+to\s+(\d{1,2}:\d{2})(?:\s*[AP]M)?)?\b/gi;

// Lines that look like questions or follow-up text, not venue names
const NON_VENUE_STARTS = [
  /^what\s/i,
  /^do you\s/i,
  /^also,?\s/i,
  /^i want\s/i,
  /^can you\s/i,
  /^could you\s/i,
  /^would you\s/i,
  /^let me\s/i,
  /^just to\s/i,
  /^if you\s/i,
  /^and\s+/i,
  /^or\s+/i,
  /^please\s/i,
  /^notify me\s/i,
  /^alert me\s/i,
  /^confirm\s/i,
  /^(\d{4}-\d{2}-\d{2})/,
];

function looksLikeVenueName(name) {
  if (!name || name.length < 2 || name.length > 80) return false;
  if (/\?/.test(name)) return false;
  const t = name.trim();
  if (NON_VENUE_STARTS.some((re) => re.test(t))) return false;
  return true;
}

function cleanLine(line) {
  if (!line || typeof line !== "string") return "";
  return line
    .replace(/^\d+\.\s*/, "")
    .replace(/\bTimes\s*:\s*/gi, "")
    .trim();
}

/**
 * @param {string} content - Full assistant message text
 * @returns {{ name: string, times: string[] }[]} - Non-empty only if 2+ venues found
 */
export function parseRestaurantListFromMessage(content) {
  if (!content || typeof content !== "string") return [];
  const lines = content.split(/\n/).map((l) => cleanLine(l)).filter(Boolean);
  const items = [];
  const timeOnly = /^\s*(\d{1,2}:\d{2}(?:\s*[AP]M)?(?:\s*[,&\s]+(?:\d{1,2}:\d{2}(?:\s*[AP]M)?))*)\s*$/i;
  let pendingTimes = [];

  for (const line of lines) {
    const times = [];
    const re = new RegExp(TIME_PATTERN.source, "gi");
    let m;
    while ((m = re.exec(line)) !== null) {
      times.push(m[2] ? `${m[1]}–${m[2]}` : m[1]);
    }
    const rest = line
      .replace(/\b\d{1,2}:\d{2}(?:\s*[AP]M)?(?:\s+to\s+\d{1,2}:\d{2}(?:\s*[AP]M)?)?\b/gi, "")
      .replace(/,+\s*$/, "")
      .replace(/\s+/g, " ")
      .trim();

    if (timeOnly.test(line)) {
      pendingTimes = times.length ? times : pendingTimes;
      continue;
    }
    const name = rest || line.trim();
    if (!looksLikeVenueName(name)) continue;
    const useTimes = times.length ? times : pendingTimes;
    pendingTimes = [];
    items.push({ name, times: useTimes });
  }

  return items.length >= 2 ? items : [];
}
