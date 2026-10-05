'use client';

import { ArrowUpRight } from 'lucide-react';
import type { FooterProps, Locale } from './types';
import { AINAUTEN_SHELL_CONTAINER_CLASS } from './shellConstants';
import {
  AINAUTEN_APPS_BY_CATEGORY,
  AINAUTEN_COMMUNITY,
  AINAUTEN_CONTACT,
  AINAUTEN_DEEP_DIVES,
  AINAUTEN_HOME,
  AINAUTEN_IMPRINT,
  AINAUTEN_JOURNEY,
  AINAUTEN_LEARNING_PLATFORM,
  AINAUTEN_PRIVACY,
  AINAUTEN_TERMS,
  getAinautenAppCategoryLabel,
  getAinautenAppLabel,
} from './appRegistry';

const labels: Record<Locale, {
  aiDisclaimer: string;
  copyright: string;
  apps: string;
  membership: string;
  about: string;
}> = {
  de: {
    aiDisclaimer: 'Inhalte werden mit AI-Unterstützung erstellt und kuratiert.',
    copyright: '© 2024-2026 AInauten',
    apps: 'Alle Tools',
    membership: 'Membership',
    about: 'Über uns',
  },
  en: {
    aiDisclaimer: 'Content is created and curated with AI assistance.',
    copyright: '© 2024-2026 AInauten',
    apps: 'All Tools',
    membership: 'Membership',
    about: 'About',
  },
};

const FOOTER_GROUPS: Array<{
  title: 'AInauten' | 'membership' | 'about';
  links: Array<{ label: Record<Locale, string>; href: string }>;
}> = [
  {
    title: 'AInauten',
    links: [
      { label: { de: 'AInauten.com', en: 'AInauten.com' }, href: AINAUTEN_HOME },
      { label: { de: 'Newsletter', en: 'Newsletter' }, href: AINAUTEN_HOME },
      { label: { de: 'AInauten Journey', en: 'AInauten Journey' }, href: AINAUTEN_JOURNEY },
    ],
  },
  {
    title: 'membership',
    links: [
      { label: { de: 'AI Automation Community', en: 'AI Automation Community' }, href: AINAUTEN_COMMUNITY },
      { label: { de: 'AInauten Lernplattform', en: 'AInauten Learning Platform' }, href: AINAUTEN_LEARNING_PLATFORM },
      { label: { de: 'AInauten Deep-Dives', en: 'AInauten Deep Dives' }, href: AINAUTEN_DEEP_DIVES },
    ],
  },
  {
    title: 'about',
    links: [
      { label: { de: 'Impressum', en: 'Legal Notice' }, href: AINAUTEN_IMPRINT },
      { label: { de: 'Datenschutz', en: 'Privacy Policy' }, href: AINAUTEN_PRIVACY },
      { label: { de: 'AGB', en: 'Terms' }, href: AINAUTEN_TERMS },
      { label: { de: 'Kontakt', en: 'Contact' }, href: AINAUTEN_CONTACT },
    ],
  },
] as const;

/**
 * AInauten Footer Component
 *
 * Unified footer for all AInauten web properties.
 * Features complete cross-tool links, legal pages, membership links, and optional newsletter signup.
 */
export function Footer({
  locale = 'de',
  variant = 'full',
  showNewsletter = false,
  showAppMap = true,
  className = '',
}: FooterProps) {
  const l = labels[locale];
  return (
    <footer className={`border-t border-[var(--border)] bg-[var(--bg-muted)] ${className}`}>
      <div className={`${AINAUTEN_SHELL_CONTAINER_CLASS} ainauten-shell-container py-8`}>
        {showNewsletter && (
          <div className="mb-8 flex flex-col items-center gap-4 rounded-xl border border-[var(--border)] bg-[var(--bg-card)] p-6 text-center">
            <div>
              <h3 className="text-lg font-semibold text-[var(--text-primary)]">
                {locale === 'de' ? 'Bleib auf dem Laufenden' : 'Stay Updated'}
              </h3>
              <p className="text-sm text-[var(--text-muted)]">
                {locale === 'de'
                  ? 'Dein wöchentliches AI-Briefing direkt in deinen Posteingang.'
                  : 'Your weekly AI briefing delivered directly to your inbox.'}
              </p>
            </div>
            <a
              href={AINAUTEN_HOME}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-lg bg-[var(--accent-active-bg)] px-5 py-2.5 text-sm font-medium text-[var(--accent-active-fg)] transition-opacity hover:opacity-90"
            >
              {locale === 'de' ? 'Kostenlos abonnieren' : 'Subscribe Free'}
              <ArrowUpRight className="h-4 w-4" />
            </a>
          </div>
        )}

        <div className="grid grid-cols-2 gap-8 lg:grid-cols-5">
          {showAppMap && (
            <div className="col-span-2 md:col-span-2">
              <h4 className="mb-3 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
                {l.apps}
              </h4>
              <div className="grid gap-4 sm:grid-cols-2">
                {AINAUTEN_APPS_BY_CATEGORY.map((group) => (
                  <div key={group.category}>
                    <p className="mb-2 text-[11px] font-bold uppercase tracking-[0.13em] text-[var(--accent)]">
                      {getAinautenAppCategoryLabel(group.category, locale)}
                    </p>
                    <ul className="space-y-2">
                      {group.apps.map((app) => (
                        <li key={app.id}>
                          <a
                            href={app.href}
                            className="text-sm text-[var(--text-secondary)] transition-colors hover:text-[var(--accent)]"
                          >
                            {getAinautenAppLabel(app, locale)}
                          </a>
                        </li>
                      ))}
                    </ul>
                  </div>
                ))}
              </div>
            </div>
          )}

          {FOOTER_GROUPS.map((group) => (
            <div key={group.title}>
              <h4 className="mb-3 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
                {group.title === 'membership' ? l.membership : group.title === 'about' ? l.about : group.title}
              </h4>
              <ul className="space-y-2">
                {group.links.map((link) => (
                  <li key={`${group.title}-${link.label.de}-${link.href}`}>
                    <a
                      href={link.href}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="ainauten-footer-link inline-flex items-center gap-1 text-sm text-[var(--text-secondary)] transition-colors hover:text-[var(--accent)]"
                    >
                      {link.label[locale]}
                      <ArrowUpRight className="h-3 w-3" />
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-8 flex flex-col items-center gap-2 border-t border-[var(--border)] pt-6 text-center">
          <p className="text-xs text-[var(--text-muted)]">
            {l.aiDisclaimer}
          </p>
          <p className="text-xs text-[var(--text-muted)]">
            {l.copyright}
          </p>
        </div>
      </div>
    </footer>
  );
}

export default Footer;
