/**
 * The icon set: line drawings on one 24-unit grid, no dependency.
 *
 * The navigation used 7px squares. They were honest placeholders and they made
 * the whole app read as a wireframe - five identical dots tell you nothing about
 * where you are going, and on the tab bar they are the only thing a phone shows
 * at a glance.
 *
 * WHY NOT AN ICON LIBRARY. Every one of them ships hundreds of glyphs drawn to
 * somebody else's grid and weight, and this app already has a drawing style: the
 * plants are procedural line-and-fill work with soft joins. Icons that came from
 * a package would sit next to them looking imported. These are drawn to the same
 * stroke weight as the plant outlines and use the same rounded joins, so a leaf
 * in the nav and a leaf in the garden look related.
 *
 * All of them inherit `currentColor` and scale from font-size, so a themed
 * button colours its icon without anything being passed down.
 */

export type IconName =
  // navigation
  | "focus" | "garden" | "shelf" | "stats" | "settings"
  | "catalogue" | "achievements" | "journal"
  // states and marks
  | "lock" | "star" | "check" | "sprout" | "leaf" | "flower"
  | "sparkle" | "expand" | "level" | "clock";

interface Props {
  name: IconName;
  /** Multiples of the current font size, so icons scale with their text. */
  size?: number;
  className?: string;
}

/** One place for the qualities that make them look like a set rather than a pile. */
const STROKE = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.7,
  strokeLinecap: "round",
  strokeLinejoin: "round",
} as const;

const PATHS: Record<IconName, React.ReactNode> = {
  // A dial with a hand: the focus timer, not a generic clock face.
  focus: <>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 7.5V12l3 2" />
  </>,
  // Two plants in a bed. The ground line is what stops it reading as a bouquet.
  garden: <>
    <path d="M3.5 19h17" />
    <path d="M8 19v-5" /><path d="M8 14c-2.4 0-3.5-1.4-3.5-3.2C6.6 10.8 8 12 8 14Z" />
    <path d="M8 14c2.4 0 3.5-1.4 3.5-3.2C9.4 10.8 8 12 8 14Z" />
    <path d="M16 19v-7" /><path d="M16 12c0-2.6 1.3-4.2 3.5-4.6C19.3 10 18.2 12 16 12Z" />
  </>,
  // A potted plant standing ON a board. The first attempt hung the pot below the
  // line and read as a mushroom at 16px; the pot belongs above the shelf, and it
  // needs the tapered sides or it is just a box.
  shelf: <>
    <path d="M3.5 20h17" />
    <path d="M9 20V13.5h6V20" />
    <path d="M8.2 13.5h7.6" />
    <path d="M12 13.5V9.5" />
    <path d="M12 9.5C9.9 9.5 9 8.4 9 6.9c2.1 0 3 1 3 2.6Z" />
    <path d="M12 9.5c2.1 0 3-1.1 3-2.6-2.1 0-3 1-3 2.6Z" />
  </>,
  // Bars that step up, because the statistics screen is about accumulation.
  stats: <>
    <path d="M4 20h16" />
    <path d="M7 20v-4.5" /><path d="M12 20V10" /><path d="M17 20V6" />
  </>,
  // Sliders rather than a cog: these are preferences, not machinery.
  settings: <>
    <path d="M5 8h9" /><path d="M18 8h1.5" />
    <path d="M5 16h3" /><path d="M12 16h7.5" />
    <circle cx="16" cy="8" r="2" /><circle cx="10" cy="16" r="2" />
  </>,
  // A specimen page: the plant, pressed and recorded.
  catalogue: <>
    <path d="M5 4.5h14v15H5z" />
    <path d="M12 15V9.5" />
    <path d="M12 9.5c-1.7 0-2.6-1-2.6-2.4C11 7.2 12 8.1 12 9.5Z" />
    <path d="M12 9.5c1.7 0 2.6-1 2.6-2.4C13 7.2 12 8.1 12 9.5Z" />
  </>,
  // A rosette. Recognisable at 16px, which a trophy is not.
  achievements: <>
    <circle cx="12" cy="9.5" r="5" />
    <path d="M9 14 7.5 21l4.5-2.3L16.5 21 15 14" />
  </>,
  // An open book with a leaf on the page.
  journal: <>
    <path d="M4 5.5h6a2 2 0 0 1 2 2V19a2 2 0 0 0-2-2H4Z" />
    <path d="M20 5.5h-6a2 2 0 0 0-2 2V19a2 2 0 0 1 2-2h6Z" />
  </>,

  lock: <>
    <rect x="5" y="10.5" width="14" height="9" rx="2" />
    <path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5" />
  </>,
  star: <path d="m12 4 2.4 5 5.6.7-4 3.9 1 5.4-5-2.7-5 2.7 1-5.4-4-3.9 5.6-.7Z" />,
  check: <path d="m5 12.5 4.5 4.5L19 7.5" />,
  sprout: <>
    <path d="M12 20v-7" />
    <path d="M12 13c-3 0-4.5-1.8-4.5-4.2C10.5 8.6 12 10.2 12 13Z" />
    <path d="M12 13c3 0 4.5-1.8 4.5-4.2C13.5 8.6 12 10.2 12 13Z" />
  </>,
  leaf: <>
    <path d="M5 19C5 11 10 6.5 19 6c.5 8.5-4 13-14 13Z" />
    <path d="M5 19c3.5-3.5 6.8-6.2 11-8.5" />
  </>,
  // Four round petals and a centre. The first version used teardrop petals at
  // four angles and collapsed into a blob below about 20px - circles survive the
  // shrink because they stay circles.
  flower: <>
    <circle cx="12" cy="8.6" r="2.4" />
    <circle cx="7.9" cy="8.6" r="2.4" />
    <circle cx="16.1" cy="8.6" r="2.4" />
    <circle cx="12" cy="4.6" r="2.4" />
    <path d="M12 11.2V20" />
    <path d="M12 15.5c2.3 0 3.4-1.2 3.4-2.9-2.3 0-3.4 1.1-3.4 2.9Z" />
  </>,
  sparkle: <>
    <path d="M12 4.5 13.4 9 18 10.5 13.4 12 12 16.5 10.6 12 6 10.5 10.6 9Z" />
    <path d="M18 16.5 18.6 18.4 20.5 19 18.6 19.6 18 21.5 17.4 19.6 15.5 19 17.4 18.4Z" />
  </>,
  expand: <>
    <path d="M4.5 9.5v-5h5" /><path d="M19.5 14.5v5h-5" />
    <path d="M4.5 4.5 10 10" /><path d="M19.5 19.5 14 14" />
  </>,
  level: <>
    <path d="M12 4.5 5 11h4v8.5h6V11h4Z" />
  </>,
  clock: <>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 7v5.2l3.4 2" />
  </>,
};

export function Icon({ name, size = 1.15, className }: Props) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={`${size}em`}
      height={`${size}em`}
      // Decorative by default: every place these are used already has a text
      // label beside them, and a screen reader announcing "leaf icon, Garden"
      // is worse than announcing "Garden".
      aria-hidden="true"
      focusable="false"
      className={className}
      {...STROKE}
    >
      {PATHS[name]}
    </svg>
  );
}
