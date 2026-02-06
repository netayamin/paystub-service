import { useMemo } from "react";

/** Match a single time e.g. 19:00 or 7:30 PM; also "18:15 to 21:45" style range. */
const TIME_PATTERN = /\b(\d{1,2}:\d{2})(?:\s*[AP]M)?(?:\s+to\s+(\d{1,2}:\d{2})(?:\s*[AP]M)?)?\b/gi;

function segmentTextWithTimeBadges(text) {
  if (!text || typeof text !== "string") return [{ type: "text", value: text || "" }];
  const segments = [];
  let lastIndex = 0;
  let m;
  const re = new RegExp(TIME_PATTERN.source, "gi");
  while ((m = re.exec(text)) !== null) {
    if (m.index > lastIndex) {
      segments.push({ type: "text", value: text.slice(lastIndex, m.index) });
    }
    const range = m[2] ? `${m[1]}–${m[2]}` : m[1];
    segments.push({ type: "time", value: range });
    lastIndex = re.lastIndex;
  }
  if (lastIndex < text.length) {
    segments.push({ type: "text", value: text.slice(lastIndex) });
  }
  return segments.length ? segments : [{ type: "text", value: text }];
}

/** Strip leading "1. ", "2. ", the "Times:" label, and the comma before the first time. */
function cleanLine(line) {
  if (!line || typeof line !== "string") return line || "";
  return line
    .replace(/^\d+\.\s*/, "")
    .replace(/\bTimes\s*:\s*/gi, "")
    .replace(/(.*?),\s*(\d{1,2}:\d{2}(?:\s*[AP]M)?)/i, "$1$2")
    .trim();
}

/**
 * Renders message content with time badges. Splits by newlines; strips leading numbers and "Times:" for readability.
 */
export function MessageWithVenueRatings({ content, placeholder }) {
  const linesSegments = useMemo(() => {
    if (!content || typeof content !== "string") return [];
    const lines = content.split(/\n/);
    return lines.map((line) => segmentTextWithTimeBadges(cleanLine(line)));
  }, [content]);

  if (content == null && placeholder) {
    return <span>{placeholder}</span>;
  }

  return (
    <span className="block">
      {linesSegments.map((segments, lineIndex) => (
        <div key={lineIndex} className="mb-1.5 min-h-[1.25em] last:mb-0">
          <span className="inline-flex flex-wrap items-center gap-1">
            {segments.map((part, j) =>
              part.type === "time" ? (
                <span
                  key={j}
                  className="inline-flex shrink-0 rounded bg-muted px-1.5 py-0.5 font-mono text-[11px] tabular-nums text-muted-foreground"
                >
                  {part.value}
                </span>
              ) : (
                <span key={j}>{part.value}</span>
              )
            )}
          </span>
        </div>
      ))}
    </span>
  );
}
