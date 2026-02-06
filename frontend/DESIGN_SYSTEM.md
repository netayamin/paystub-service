# Design System (Concierge UI)

- **Tokens live in `src/index.css`** inside `@theme`. Colors, fonts, and radius are defined there. Shadcn UI components pick up semantic names (`--color-primary`, `--color-background`, etc.); layout uses design tokens (`--color-off-white`, `--color-brand-black`, etc.) via Tailwind utilities.
- **Do not override shadcn UI component source files.** Style only via:
  - Theme variables in `index.css` (affects all shadcn components).
  - Tailwind classes when composing (e.g. `className="..."` on wrappers or on shadcn components).
- **Layout utilities** in `index.css`: `.linen-bg` (dot pattern background), `.no-scrollbar` (hide scrollbar).
- **Palette:** off-white, studio-gray, brand-black, brand-blue, border-subtle, agent-green. Use as Tailwind classes: `bg-off-white`, `text-brand-black`, `border-border-subtle`, etc.
