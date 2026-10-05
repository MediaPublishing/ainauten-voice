import type { Locale } from './types';

export type AinautenAppId =
  | 'search'
  | 'news'
  | 'widget'
  | 'design'
  | 'promptlinks'
  | 'prompts'
  | 'share'
  | 'privacy'
  | 'skills'
  | 'loops'
  | 'nauti'
  | 'help';

export type AinautenAppType = 'tool' | 'content' | 'support';
export type AinautenAppCategory =
  | 'News, Support & Wissen'
  | 'Prompts, Daten & Teilen'
  | 'Agenten & Coding';

export interface AinautenApp {
  id: AinautenAppId;
  label: string;
  shortLabel?: string;
  href: string;
  type: AinautenAppType;
  category: AinautenAppCategory;
  summary: string;
  why?: string;
  audience?: string;
  when?: string;
  aliases?: string[];
}

export const AINAUTEN_HOME = 'https://www.ainauten.com/';
export const AINAUTEN_JOURNEY = 'https://vip.ainauten.com/';
export const AINAUTEN_COMMUNITY = 'https://vip.ainauten.com/ai-automation-expert';
export const AINAUTEN_LEARNING_PLATFORM = 'https://learn.ainauten.com/';
export const AINAUTEN_DEEP_DIVES = 'https://www.ainauten.com/upgrade';
export const AINAUTEN_IMPRINT = 'https://learn.ainauten.com/impressum/';
export const AINAUTEN_PRIVACY = 'https://learn.ainauten.com/privacy/';
export const AINAUTEN_TERMS = 'https://learn.ainauten.com/agb/';
export const AINAUTEN_CONTACT = 'https://learn.ainauten.com/contact/';
export const AINAUTEN_NAUTI_MARK = '/nauti-logo.png';

export const AINAUTEN_APP_CATEGORIES: AinautenAppCategory[] = [
  'News, Support & Wissen',
  'Prompts, Daten & Teilen',
  'Agenten & Coding',
];

const AINAUTEN_APP_LABELS_EN: Partial<Record<AinautenAppId, string>> = {
  search: 'Newsletter Search',
  news: "Nauti's AI News",
};

const AINAUTEN_APP_CATEGORY_LABELS_EN: Record<AinautenAppCategory, string> = {
  'News, Support & Wissen': 'News, Support & Knowledge',
  'Prompts, Daten & Teilen': 'Prompts, Data & Sharing',
  'Agenten & Coding': 'Agents & Coding',
};

export const AINAUTEN_APPS: AinautenApp[] = [
  {
    id: 'search',
    label: 'Newsletter Suche',
    shortLabel: 'Suche',
    href: 'https://search.ainauten.com/',
    type: 'content',
    category: 'News, Support & Wissen',
    summary: 'Suche über den AInauten-Newsletter, Quick News und Deep-Dives.',
  },
  {
    id: 'news',
    label: 'Nautis AI News',
    shortLabel: 'News',
    href: 'https://news.ainauten.com/',
    type: 'content',
    category: 'News, Support & Wissen',
    summary: 'Kuratierter AI-News-Stream mit Quellen, Kategorien und AInauten-Einordnung.',
  },
  {
    id: 'help',
    label: 'Knowledge Base',
    shortLabel: 'Help',
    href: 'https://help.ainauten.com/',
    type: 'support',
    category: 'News, Support & Wissen',
    summary: 'Knowledge Base für AI-Tools, Automatisierung und Prompting.',
  },
  {
    id: 'nauti',
    label: 'Nauti Chatbot',
    shortLabel: 'Nauti',
    href: 'https://nauti.ainauten.com/',
    type: 'support',
    category: 'News, Support & Wissen',
    summary: 'AI Automation Expert Assistent im AInauten-Kontext.',
  },
  {
    id: 'widget',
    label: 'AI Summary Widget',
    shortLabel: 'Widget',
    href: 'https://widget.ainauten.com/',
    type: 'tool',
    category: 'Prompts, Daten & Teilen',
    summary: 'Embed-Widget, um Seiteninhalte direkt in AI-Tools zu öffnen.',
    aliases: ['https://widgets.ainauten.com/'],
  },
  {
    id: 'promptlinks',
    label: 'PromptLinks',
    shortLabel: 'Links',
    href: 'https://promptlinks.ainauten.com/',
    type: 'tool',
    category: 'Prompts, Daten & Teilen',
    summary: 'Wandelt Prompts in klickbare Links für AI-Chats um.',
  },
  {
    id: 'prompts',
    label: 'AInauten Prompts',
    shortLabel: 'Prompts',
    href: 'https://prompts.ainauten.com/',
    type: 'tool',
    category: 'Prompts, Daten & Teilen',
    summary: 'Kuratierte Prompt-Datenbank der AInauten.',
  },
  {
    id: 'privacy',
    label: 'Privacy Filter',
    shortLabel: 'Privacy',
    href: 'https://privacy.ainauten.com/',
    type: 'tool',
    category: 'Prompts, Daten & Teilen',
    summary: 'Browserlokales Tool zum Maskieren personenbezogener Daten.',
  },
  {
    id: 'design',
    label: 'DESIGN.md Generator',
    shortLabel: 'DESIGN.md',
    href: 'https://design.ainauten.com/',
    type: 'tool',
    category: 'Agenten & Coding',
    summary: 'Erstellt aus öffentlichen Webseiten eine agententaugliche DESIGN.md.',
  },
  {
    id: 'skills',
    label: 'Skills Creator',
    shortLabel: 'Skills',
    href: 'https://skills.ainauten.com/',
    type: 'tool',
    category: 'Agenten & Coding',
    summary: 'Hilft beim Erstellen wiederverwendbarer Arbeitsanweisungen für AI-Agenten.',
  },
  {
    id: 'loops',
    label: 'Loops',
    shortLabel: 'Loops',
    href: 'https://loops.ainauten.com/',
    type: 'tool',
    category: 'Agenten & Coding',
    summary: 'Arbeitsfläche für wiederholbare Agenten- und Coding-Loops im AInauten-System.',
  },
];

export const AINAUTEN_APPS_BY_CATEGORY = AINAUTEN_APP_CATEGORIES.map((category) => ({
  category,
  apps: AINAUTEN_APPS.filter((app) => app.category === category),
})).filter((group) => group.apps.length > 0);

export const AINAUTEN_APPS_BY_ID = Object.fromEntries(
  AINAUTEN_APPS.map((app) => [app.id, app]),
) as Record<AinautenAppId, AinautenApp>;

const LEGACY_PRODUCT_TO_APP: Record<string, AinautenAppId> = {
  NEWS: 'news',
  PROMPTS: 'prompts',
  SHARE: 'share',
  SEARCH: 'search',
  WIDGET: 'widget',
  WIDGETS: 'widget',
  LINKS: 'promptlinks',
  PROMPTLINKS: 'promptlinks',
  HELP: 'help',
  PRIVACY: 'privacy',
  SKILLS: 'skills',
  DESIGN: 'design',
  LOOPS: 'loops',
  NAUTI: 'nauti',
};

export function resolveAinautenAppId(product: string): AinautenAppId | undefined {
  const normalized = product.trim().toLowerCase().replace(/[\s_]+/g, '-');
  const direct = AINAUTEN_APPS.find((app) => app.id === normalized);

  if (direct) {
    return direct.id;
  }

  return LEGACY_PRODUCT_TO_APP[product.trim().toUpperCase()];
}

export function getAinautenAppLabel(app: AinautenApp, locale: Locale = 'de') {
  if (locale === 'en') return AINAUTEN_APP_LABELS_EN[app.id] || app.label;

  return app.label;
}

export function getAinautenAppCategoryLabel(category: AinautenAppCategory, locale: Locale = 'de') {
  return locale === 'en' ? AINAUTEN_APP_CATEGORY_LABELS_EN[category] : category;
}
