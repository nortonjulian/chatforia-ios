# Neon Premium: cross-platform design specification

This is the Electric Cobalt × Ultraviolet **candidate** for Neon on iOS, pending physical-iPhone review. Android and web should map these values and state rules into their existing theme systems after approval; neither platform is changed by this branch. The other seven themes retain their approved Build 48/49 appearance.

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
| Accent / selected tab | `#7772F8` | Routine actions and selection |
| Electric cobalt | `#4667F5` | Dominant gradient start, repeated through 58% of the fill |
| Ultraviolet | `#7772F8` | Gradient transition at 86% |
| Icy-blue highlight | `#B2C7FF` | Restrained gradient endpoint |
| Gradient ink | `#000000` | Opaque text and meaningful icons on the cobalt-to-icy fills; near-black `#0A0B20` misses 4.5:1 on cobalt |
| Disabled fill | `#302A4A` | Disabled gradient control replacement |
| Disabled foreground | `#AFA7CA` | Text and icons on disabled fill |

## Shared visual rules and iOS rendering reference

| iOS component | Implemented fill and direction | Foreground |
| --- | --- | --- |
| Primary gradient buttons, including the main dial-pad Call button | `#4667F5` at 0% and 58%, `#7772F8` at 86%, `#B2C7FF` at 100%; leading to trailing | Opaque `#000000` |
| Outgoing SMS and Chatforia message bubbles | Same four stops, **top leading to bottom trailing** | Opaque `#000000` for text, metadata, and audio/microphone symbols |
| Send, microphone, attachment-send, and Ria composer controls | Same four stops, leading to trailing | Opaque `#000000` |
| Incoming message bubbles | Solid `#29204B` | `#F4F1FF` |
| Call History call/video actions, dial-pad contact suggestions, and SMS media playback | Solid accent `#7772F8`; **no gradient** | Dark ink selected by the existing accent-control foreground role |

The button-gradient role also fills unread and highlighted plan badges. The composer-gradient role fills outgoing Ria responses. These decorative fills use their role's leading-to-trailing direction but do not have pressed or disabled states. Each normal gradient has a shape-contained 3% white contrast lift over its exact palette stops; this compensates for iOS rendered-color rounding at cobalt. Existing in-call controls retain their functional solid dark, blue active, and red End fills; they do not use the Neon button gradient. The iOS active-call background blends the screen and card surfaces from top to bottom, while the dial-pad background blends two screen-surface opacities from top to bottom. These screen treatments and other existing one-off gradients are not new cross-platform semantic roles.

- Pressed **gradient controls** retain their stops and receive a shape-clipped 6% white overlay; retain the same black ink foreground. This restrained lightening distinguishes the pressed state while keeping the cobalt stop above the text-contrast threshold. Message bubbles are not press-state controls. Do not add glow or a backing rectangle.
- Disabled gradient controls use solid `#302A4A` with `#AFA7CA` foreground, without an additional opacity reduction or glow. Disabled actions remain non-interactive.
- Selected accent-filled controls use `#7772F8` with dark ink. Routine toolbar icons use the accent on the screen surface; navigation titles and primary content use `#F4F1FF`. Secondary labels use `#B9B2D5` on dark surfaces. Composer fields use `#241D42` with `#756BA5` outline; media cards use the card surface and existing semantic control colors.
- Android and web should share the token values, foreground hierarchy, gradient role and direction for equivalent components, and contrast targets. Use their native rendering and existing component geometry rather than copying SwiftUI-specific view structure or in-call control states. Retain existing hierarchy, spacing, bubble shapes, navigation, animation, and accessibility labels. Keep authentication, messaging, calling, billing, and media logic unchanged. Do not hardcode platform-specific colors where a theme token exists.

## Accessibility acceptance

Measure *rendered* fills with the actual compositing and both system appearances. Normal body text and meaningful icons on gradients target at least 4.5:1, pressed at least 4.5:1, and disabled labels at least 4.5:1 for readability even though disabled controls have different WCAG treatment. Non-text boundaries and actionable icons target at least 3:1 against adjacent surfaces. Check the full diagonal of outgoing bubbles, the full width of buttons, and both endpoints of reverse composer fills. Confirm selected, pressed, disabled, and VoiceOver states on physical devices before release.

The uncomposited source-color contrast at the darkest cobalt stop is 4.52:1 with black ink; at ultraviolet it is 5.55:1, and at icy blue it is 12.51:1. iOS pixel sampling without the 3% lift measured only 4.47–4.48:1 at cobalt; the lift is required for the rendered threshold. On an iPhone 18 Pro iOS 27 simulator, pixel-sampled minimums with the lift were 4.72:1 for outgoing bubbles and 4.73:1 for button and composer fills, in both light and dark appearances. Synthetic pressed fills measured 4.95:1 and disabled fills measured 5.92:1. Only controls use pressed and disabled states in the interface. Physical-iPhone visual review remains required.
