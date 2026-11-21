# Neon Premium: cross-platform design specification

This is the approved Neon-only design implemented on the iOS feature branch. Android and web should map these values into their existing theme systems; neither platform is changed by this branch. Midnight and the other six themes retain their Build 48 appearance.

## Semantic tokens

| Role | Value | Use |
| --- | --- | --- |
| Screen and composer surface | `#0D0A22` | Main background, navigation and toolbar backdrop |
| Card surface | `#211A3D` | Lists, cards, media cards, dial pad surfaces |
| Highlighted surface | `#322957` | Selected or emphasized dark-surface regions |
| Incoming bubble | `#29204B` | Received SMS and Chatforia messages |
| Composer field | `#241D42` | Text input surface |
| Surface border | `#4A3C70` | Card separation |
| Control outline | `#756BA5` | Composer and focused control outline |
| Primary text / navigation title | `#F4F1FF` | Content on dark surfaces |
| Secondary text | `#B9B2D5` | Hints, timestamps, supporting labels |
| Unselected tab icon | `#AAA3C4` | Inactive navigation |
| Accent / selected tab | `#28D7C8` | Routine actions and selection |
| Gradient ink | `#0A0B20` | Text and icons on bright two-stop fills |
| Disabled fill | `#302A4A` | Disabled gradient control replacement |
| Disabled foreground | `#AFA7CA` | Text and icons on disabled fill |

## Components and interaction states

- Primary buttons, Call controls, and outgoing message bubbles use a left-to-right `#9275EC` → `#25D8C6` gradient. Use opaque `#0A0B20` for text, icons, outgoing metadata, and audio/microphone symbols throughout the full fill.
- Send and composer buttons reverse those stops: `#25D8C6` → `#9275EC`, with the same opaque dark ink. Keep the existing control shapes and dimensions.
- Pressed gradient controls retain their stops and receive a shape-clipped 6% overlay of `#0A0B20`; retain the same ink foreground. Do not add glow or a backing rectangle.
- Disabled gradient controls use solid `#302A4A` with `#AFA7CA` foreground, without an additional opacity reduction or glow. Disabled actions remain non-interactive.
- Selected accent-filled controls use `#28D7C8` with dark ink. Routine toolbar icons use the accent on the screen surface; navigation titles and primary content use `#F4F1FF`. Secondary labels use `#B9B2D5` on dark surfaces.
- Incoming bubbles use `#29204B` with `#F4F1FF` text. Composer fields use `#241D42` and `#756BA5` outline. Media cards use the card surface and existing semantic control colors.
- Retain the existing component hierarchy, spacing, bubble shapes, navigation, animation, and accessibility labels. Keep authentication, messaging, calling, billing, and media logic unchanged. Do not hardcode platform-specific colors in component bodies where a theme token exists.

## Accessibility acceptance

Measure *rendered* fills with the actual compositing and both system appearances. Normal body text and meaningful icons on gradients target at least 4.5:1, pressed at least 4.5:1, and disabled labels at least 4.5:1 for readability even though disabled controls have different WCAG treatment. Non-text boundaries and actionable icons target at least 3:1 against adjacent surfaces. Check the full diagonal of outgoing bubbles, the full width of buttons, and both endpoints of reverse composer fills. Confirm selected, pressed, disabled, and VoiceOver states on physical devices before release.

The iOS simulator's pixel-sampled minimums across the rendered fills are 5.53:1 for normal outgoing bubbles, 5.54:1 for normal buttons, 5.59:1 for normal composer controls; 5.02:1 for pressed outgoing bubbles and buttons, 5.04:1 for pressed composer controls; and 5.92:1 for all disabled fills. These are iOS simulator measurements, not Android or browser verification.
