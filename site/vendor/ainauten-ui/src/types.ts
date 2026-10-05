/**
 * Shared types for AInauten UI components
 */

export type Locale = 'de' | 'en';

export type Product =
  | 'TOOLS'
  | 'SEARCH'
  | 'NEWS'
  | 'PROMPTS'
  | 'SHARE'
  | 'WIDGET'
  | 'WIDGETS'
  | 'LINKS'
  | 'PROMPTLINKS'
  | 'HELP'
  | 'PRIVACY'
  | 'SKILLS'
  | 'DESIGN'
  | 'LOOPS'
  | 'NAUTI'
  | 'tools'
  | 'search'
  | 'news'
  | 'prompts'
  | 'share'
  | 'widget'
  | 'widgets'
  | 'promptlinks'
  | 'help'
  | 'privacy'
  | 'skills'
  | 'design'
  | 'loops'
  | 'nauti';

export interface NavLink {
  label: string;
  href: string;
  external?: boolean;
  active?: boolean;
}

export interface HeaderProps {
  /** Current product/section name shown after AINAUTEN */
  product: Product;
  /** Product id used to highlight the active global app link */
  activeApp?: Product;
  /** Current locale for i18n */
  locale?: Locale;
  /** Visual variant for the surrounding app surface */
  variant?: 'tool' | 'content' | 'kb';
  /** Show theme toggle button */
  showThemeToggle?: boolean;
  /** Show language toggle */
  showLanguageToggle?: boolean;
  /** Optional language toggle handler for apps with client-side locale state */
  onLanguageToggle?: () => void;
  /** Show global AInauten app links */
  showGlobalNav?: boolean;
  /** Optional app-local links shown before the global links */
  localNav?: NavLink[];
  /** Optional custom action area appended to the right */
  actions?: React.ReactNode;
  /** Custom logo link href */
  logoHref?: string;
  /** Custom Nauti mark image src */
  logoSrc?: string;
  /** Additional CSS classes */
  className?: string;
}

export interface FooterProps {
  /** Current product/section */
  product?: Product;
  /** Current locale for i18n */
  locale?: Locale;
  /** Footer density */
  variant?: 'compact' | 'full';
  /** Show newsletter signup */
  showNewsletter?: boolean;
  /** Show complete app map */
  showAppMap?: boolean;
  /** Additional CSS classes */
  className?: string;
}

export interface AinautenShellProps {
  /** Shared header configuration */
  header: HeaderProps;
  /** Shared footer configuration */
  footer?: FooterProps;
  /** Main application content */
  children: React.ReactNode;
  /** Additional classes for the outer shell */
  className?: string;
}

export interface NewsletterConversionBandProps {
  /** Current locale for i18n */
  locale?: Locale;
  /** Small label above the headline */
  eyebrow?: string;
  /** Main conversion headline */
  title?: string;
  /** Supporting line below the headline */
  description?: string;
  /** CTA label */
  ctaLabel?: string;
  /** Newsletter destination */
  href?: string;
  /** Optional compact trust line */
  proof?: string;
  /** Additional CSS classes */
  className?: string;
}

export interface ThemeToggleProps {
  /** Current locale for i18n */
  locale?: Locale;
  /** Additional CSS classes */
  className?: string;
}

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  /** Button variant */
  variant?: 'primary' | 'secondary' | 'ghost' | 'outline';
  /** Button size */
  size?: 'sm' | 'md' | 'lg';
  /** Full width button */
  fullWidth?: boolean;
  /** Loading state */
  isLoading?: boolean;
}

export interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Card variant */
  variant?: 'default' | 'elevated' | 'outlined';
  /** Hover effect */
  hoverable?: boolean;
  /** Padding size */
  padding?: 'none' | 'sm' | 'md' | 'lg';
}

export interface ChipProps extends React.HTMLAttributes<HTMLSpanElement> {
  /** Chip variant */
  variant?: 'default' | 'active' | 'outline';
  /** Click handler for interactive chips */
  onClick?: () => void;
}

export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  /** Label text */
  label?: string;
  /** Error message */
  error?: string;
  /** Help text */
  helpText?: string;
}

export interface AIServiceIconProps {
  /** AI service name */
  service: 'chatgpt' | 'claude' | 'gemini' | 'grok' | 'perplexity';
  /** Icon size */
  size?: 'sm' | 'md' | 'lg';
  /** Show tooltip with service name */
  showTooltip?: boolean;
  /** Additional CSS classes */
  className?: string;
}

export interface WidgetPromoProps {
  /** Title text */
  title?: string;
  /** Description text */
  description?: string;
  /** Button text */
  buttonText?: string;
  /** Widget URL */
  widgetUrl?: string;
  /** Preview label text */
  previewLabel?: string;
  /** AI services to show in widget */
  services?: string;
  /** Widget label text */
  widgetLabel?: string;
  /** Custom prompt for the widget */
  prompt?: string;
  /** Whether to use dynamic URL in prompt */
  useDynamicPrompt?: boolean;
}
