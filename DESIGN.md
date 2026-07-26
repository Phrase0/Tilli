---
name: Tilli (Market POS)
description: A minimalist point-of-sale companion for market and pop-up vendors.
colors:
  ink: "#000000"
  paper: "#F2F2F7"
  card-surface: "#FFFFFF"
  muted: "#8E8E93"
  market-green: "#34C759"
  alert-red: "#FF3B30"
typography:
  display:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "34px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "normal"
  title1:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.2
  title2:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: 1.25
  body:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.4
  caption:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.3
rounded:
  sm: "12px"
  md: "24px"
  pill: "999px"
spacing:
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "24px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.card-surface}"
    rounded: "{rounded.md}"
    padding: "16px 24px"
  button-secondary:
    backgroundColor: "#E5E5EA"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "16px 24px"
  button-destructive:
    backgroundColor: "#E5E5EA"
    textColor: "{colors.alert-red}"
    rounded: "{rounded.md}"
    padding: "16px 24px"
  status-pill-running:
    backgroundColor: "#D8F5DE"
    textColor: "{colors.market-green}"
    rounded: "{rounded.pill}"
    padding: "4px 8px"
  status-pill-neutral:
    backgroundColor: "#E5E5EA"
    textColor: "{colors.muted}"
    rounded: "{rounded.pill}"
    padding: "4px 8px"
  card:
    backgroundColor: "{colors.card-surface}"
    rounded: "{rounded.md}"
    padding: "16px"
---

# Design System: Tilli (Market POS)

## Overview

**Creative North Star: "The Stallholder's Notebook"**

Tilli is what a market vendor opens between customers, not a storefront they invite people to admire. The system reads like a plain paper ledger a stallholder keeps under the cash box: fast to scan, impossible to misread under bad tent lighting, and completely unconcerned with impressing anyone. Every surface is white or grouped-gray, every action is spoken in black ink, and the one splash of color in the whole app is reserved for the single fact a vendor actually needs to see at a glance — is this session live right now.

This is a redesign target: it establishes the visual language shown in the reference mockups (`tilliStructure1–3.PNG`) as the system going forward. It does not describe every screen currently shipped in the codebase — several legacy pages (`AddNewProductView`, `CheckoutFlowView`, `InventoryChangeView`, and older colorful accents such as blue/orange/purple UI) predate this system and are superseded by it, not blended with it.

**Key Characteristics:**
- Monochrome by default: black, white, and two grays do almost all the work.
- One semantic accent: green, used only to mean "running / positive," never decoratively.
- Flat cards with barely-there shadows — depth is implied by fill, not lifted.
- A tight, closed type scale (28 / 22 / 16 / 12) and an equally closed spacing scale (8 / 12 / 16 / 24). Nothing floats between the steps.
- Full-bleed black CTAs with generous 24pt rounding — the app's only "loud" gesture, and it's still just black.

## Colors

The palette is almost a grayscale document with a single semantic exception. Color is never used to decorate; it is used exactly once, to answer "is this happening right now."

### Primary
- **Ink** (`#000000`): Primary CTAs, active tab/segment fills, selected states (calendar date, category filter, radio selection), headline text. This is the app's only "brand color" — there is no colored accent standing in for it.

### Secondary
- **Market Green** (`#34C759`): Exclusively the "Running" / positive-status signal (session-in-progress pill, success checkmark on completed checkout). Never used for buttons, icons, or emphasis text. If a screen has more than one green element, that's a violation, not a feature.

### Neutral
- **Paper** (`#F2F2F7`, `systemGroupedBackground`): Page background behind cards.
- **Card Surface** (`#FFFFFF`, `systemBackground`): Card, sheet, and list-row fill.
- **Muted Gray** (`#8E8E93`, `.secondary`): Secondary text — dates, subtitles, helper copy, unselected tab labels.
- **Quiet Fill** (`#E5E5EA`, `systemGray6`): Secondary button backgrounds, neutral/"completed" status pills, unselected segment track.
- **Alert Red** (`#FF3B30`, `systemRed`): Destructive text only (delete session, delete product, remove item) — never a filled button background.

### Named Rules
**The One Green Rule.** Green means "running," full stop. It never appears as a generic accent, link color, icon tint, or decorative highlight — if it's not signaling an active session or a completed payment, it isn't green.

**The No-Blue Rule.** Interactive and selected states are communicated with a solid ink fill, not a colored accent. Blue does not appear anywhere in the chrome; if a control needs to look "on," it turns black, not blue.

## Typography

**Display Font:** SF Pro (system font — no custom typeface is loaded; this is deliberate, not a placeholder).

**Character:** A single honest system face at four sizes, plus one larger display cut for the numbers that matter (today's revenue, a checkout total). No condensed, no italic, no decorative weight — the notebook doesn't have a "brand font," it has legible numbers.

### Hierarchy
- **Display** (700, 34px, 1.1): Hero monetary figures only — the dashboard's today's-revenue number, the checkout success amount. Reserve for currency, never for headings.
- **Title 1** (700, 28px, 1.2): Page titles (Events, POS, Inventory, Analytics, My).
- **Title 2** (600, 22px, 1.25): Section headers within a page (e.g. "Today", "Upcoming", a sheet's field group).
- **Body** (400, 16px, 1.4): Product names, list rows, form field values, button labels.
- **Caption** (400, 12px, 1.3): Timestamps, helper text, status-pill labels, quantity/stock counters.

### Named Rules
**The Four-Size Rule.** Every screen is composed from exactly these four sizes plus the one Display cut. A fifth size is a sign the layout needs restructuring, not a new token.

## Layout

Single-column, full-width card stacks — this is a phone-first tool used one-handed at a counter, not a responsive grid. Screens open with a Title 1 header (often with a trailing icon-only action), then a vertical rhythm of full-width cards separated by the 24pt spacing step, never by `Divider()` lines. List rows within a card use the 12pt step between rows and 16pt internal card padding. Bottom navigation is a persistent 4–5 item tab bar (Dashboard / POS / Inventory / Analytics, or Events / My on the outer level) using SF Symbols outline icons with a caption-size label. Sheets (New Event, Edit Product) stack fields top-to-bottom with a label above each input and a single full-width primary button pinned at the sheet's bottom edge.

## Elevation & Depth

Depth is almost entirely conveyed through flat color contrast (white cards on gray page background), not shadow. Where a shadow exists at all, it is a single, barely-perceptible ambient cue that a surface is a discrete card — never a directional "lifted" effect, never used to imply hover/press feedback (this is touch-first, there is no hover).

### Shadow Vocabulary
- **Card ambient** (`shadow: 0 1px 2px rgba(0,0,0,0.05)`): The only shadow in the system. Applied to every standalone card, session tile, and list-row container.

### Named Rules
**The Whisper Shadow Rule.** Shadow opacity never exceeds 0.05. If a shadow is visible enough to describe, it's too strong — depth should register as "this is a card" and nothing more.

## Shapes

Two radii, applied with total consistency: **24px** for anything a thumb taps as a primary target — cards, primary/secondary buttons, product photos, sheets — and **12px** for anything smaller or auxiliary — small buttons, list-row containers, input fields. Status pills, tags, and the segmented List/Calendar toggle use a full **capsule** (999px). There are no square corners anywhere in the system, and no third radius value.

## Components

### Buttons
- **Shape:** 24px corner radius, full width, 16px vertical padding.
- **Primary:** Ink (`#000000`) fill, white text, 16px semibold label — the app's single loudest gesture ("建立場次", "結帳", "確認收款", "立即同步").
- **Secondary:** Quiet Fill (`#E5E5EA`) background, ink text — used for "取消" and paired secondary actions.
- **Destructive:** Same Quiet Fill background as secondary, but red text — used for "刪除場次" style actions. Destructive actions are never a solid red fill; the red lives only in the label.
- **Icon-only:** Bare SF Symbol (outline), `.primary` or `.secondary` tint, no background — used for header actions (search, add, filter, back).

### Status Pills (signature component)
- **Running:** Light green fill (`#D8F5DE`) with Market Green text, capsule shape, caption-size label ("進行中"/"Running").
- **Neutral/Completed:** Quiet Fill background with Muted Gray text, same capsule shape.
- **Rule:** Exactly one status pill per card; it always sits in the trailing/top-right position of the card header.

### Cards / Containers
- **Corner Style:** 24px radius.
- **Background:** Card Surface (`#FFFFFF`) on a Paper (`#F2F2F7`) page background — the contrast between these two is the system's entire depth model.
- **Shadow Strategy:** Card ambient whisper shadow only (see Elevation & Depth).
- **Border:** None. Cards are separated by fill contrast and spacing, never a stroke.
- **Internal Padding:** 16px.

### Inputs / Fields
- **Style:** Label (caption/body weight) stacked above a plain-underline or Quiet Fill field, 12px radius, no heavy stroke box.
- **Focus:** System default keyboard-focus ring; no custom glow.
- **Optional fields:** Explicitly marked "(選填)" in the label rather than relying on an asterisk convention for required fields.

### Navigation
- **Tab bar:** SF Symbols outline icons + caption label; selected item switches to `.primary` (black) icon+label, unselected stays `.secondary` gray. No colored active-tab indicator — the icon/label darkening is the only signal.
- **Segmented control (List/Calendar):** Capsule track in Quiet Fill, selected segment is a solid ink pill with white label sliding within the track.

### Data Visualization (exception to the monochrome rule)
- **Payment-method donut/legend** (Analytics → Sales Analysis): The only place the system permits a multi-color categorical palette (e.g. green/blue/orange/gray segments for LINE Pay / 現金 / 街口支付 / 信用卡), because distinguishing ≥3 categories requires it. This palette is scoped to chart legends only and must never leak into buttons, icons, or status pills elsewhere.

## Do's and Don'ts

### Do:
- **Do** use solid ink (`#000000`) fill for every primary CTA and every "selected" state (active tab, active segment, selected calendar date, checked radio).
- **Do** keep every corner at exactly 24px or 12px, every spacing gap at exactly 8/12/16/24px, and every type size at exactly 28/22/16/12px (plus the one 34px Display cut for money).
- **Do** reserve green strictly for the "Running" status signal.
- **Do** use SF Symbols in outline style everywhere; switch to `.fill` only to indicate a selected/active icon state, never for decoration.
- **Do** separate sections with spacing and fill contrast, not `Divider()` lines.

### Don't:
- **Don't** use blue (or any color besides ink) as a button background or selected-state fill.
- **Don't** let shadow opacity exceed 0.05, and never use a shadow to imply hover — this is a touch-first tool.
- **Don't** introduce a second colored status pill or a second "meaning" for green.
- **Don't** carry forward the legacy blue/orange/purple accents, non-standard radii (4/8/10/25/30px), or ad hoc font sizes still present in older, pre-redesign screens — those are debt this system replaces, not precedent to match.
- **Don't** use colored icons outside the Data Visualization exception.
