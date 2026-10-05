'use client';

import { useState } from 'react';
import { ArrowUpRight, ChevronDown, Menu, X } from 'lucide-react';
import type { HeaderProps, Locale } from './types';
import { ThemeToggle } from './ThemeToggle';
import { AINAUTEN_SHELL_CONTAINER_CLASS } from './shellConstants';
import {
  AINAUTEN_APPS_BY_CATEGORY,
  AINAUTEN_APPS_BY_ID,
  AINAUTEN_HOME,
  AINAUTEN_NAUTI_MARK,
  getAinautenAppCategoryLabel,
  getAinautenAppLabel,
  resolveAinautenAppId,
} from './appRegistry';

const labels: Record<Locale, {
  menuClose: string;
  menuOpen: string;
  allTools: string;
  mainSite: string;
}> = {
  de: {
    menuClose: 'Menü schließen',
    menuOpen: 'Menü öffnen',
    allTools: 'Alle Tools',
    mainSite: 'AInauten',
  },
  en: {
    menuClose: 'Close menu',
    menuOpen: 'Open menu',
    allTools: 'All Tools',
    mainSite: 'AInauten',
  },
};

/**
 * AInauten Header Component
 *
 * Unified header for all AInauten web properties.
 * Features Nauti branding, app navigation, theme toggle, and language switcher.
 */
export function Header({
  product,
  activeApp,
  locale = 'de',
  showThemeToggle = true,
  showLanguageToggle = true,
  onLanguageToggle,
  showGlobalNav = true,
  localNav = [],
  actions,
  logoHref,
  logoSrc,
  className = '',
}: HeaderProps) {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [toolsMenuOpen, setToolsMenuOpen] = useState(false);
  const l = labels[locale];
  const activeId = resolveAinautenAppId(String(activeApp || product));
  const currentApp = activeId ? AINAUTEN_APPS_BY_ID[activeId] : undefined;
  const productLabel = (currentApp?.label || String(product)).replace(/^AInauten\s+/i, '');
  const href = logoHref || currentApp?.href || '/';
  const markSrc = logoSrc || AINAUTEN_NAUTI_MARK;
  const showTopNavigation = localNav.length > 0;
  const navLinkClass =
    'inline-flex h-[var(--h-control)] box-border items-center rounded-full px-3 text-sm font-medium text-[var(--text-muted)] transition-colors hover:bg-[var(--accent-light)] hover:text-[var(--text-primary)]';
  const activeLinkClass =
    'inline-flex h-[var(--h-control)] box-border items-center rounded-full bg-[var(--accent-active-bg)] px-3 text-sm font-semibold text-[var(--accent-active-fg)]';
  const controlClass =
    'inline-flex h-[var(--h-control)] box-border items-center justify-center rounded-lg border border-[var(--border-strong)] bg-[var(--bg-secondary)] px-3 text-sm font-semibold text-[var(--text-secondary)] transition-colors hover:bg-[var(--accent-light)] hover:text-[var(--text-primary)]';

  const closeMobileMenu = () => {
    setMobileMenuOpen(false);
    setToolsMenuOpen(false);
  };

  return (
    <header className={`ainauten-shell-header sticky top-0 z-50 border-b border-[var(--border)] bg-[var(--bg-secondary)] ${className}`}>
      <div className={`${AINAUTEN_SHELL_CONTAINER_CLASS} ainauten-shell-container`}>
        <div className="flex h-14 items-center justify-between">
          <a href={href} className="flex min-w-0 items-center gap-3" aria-label={`AINAUTEN ${productLabel}`}>
            <span className="grid h-8 w-8 shrink-0 place-items-center">
              <img
                src={markSrc}
                alt="Nauti"
                className="h-7 w-7 object-contain"
                width="28"
                height="28"
              />
            </span>
            <span className="min-w-0 overflow-hidden whitespace-normal font-sans text-[11px] font-bold uppercase leading-[1.15] tracking-[0.07em] text-[var(--text-primary)] sm:truncate sm:text-sm sm:leading-normal">
              AINAUTEN <span className="text-[var(--accent)]">{productLabel}</span>
            </span>
          </a>

          {showTopNavigation && (
            <nav className="hidden min-w-0 flex-1 items-center justify-center gap-1 px-4 lg:flex" aria-label="Tool-Navigation">
              {localNav.map((item) => (
                <a
                  key={`${item.href}-${item.label}`}
                  href={item.href}
                  target={item.external ? '_blank' : undefined}
                  rel={item.external ? 'noopener noreferrer' : undefined}
                  className={item.active ? activeLinkClass : navLinkClass}
                  aria-current={item.active ? 'page' : undefined}
                >
                  {item.label}
                </a>
              ))}
            </nav>
          )}

          <div className="flex items-center gap-2">
            {actions}
            {showGlobalNav && (
              <div className="relative hidden lg:block">
                <button
                  type="button"
                  className={`${controlClass} gap-1.5`}
                  aria-expanded={toolsMenuOpen}
                  aria-haspopup="true"
                  onClick={() => setToolsMenuOpen((open) => !open)}
                >
                  {l.allTools}
                  <ChevronDown className="h-4 w-4" aria-hidden="true" />
                </button>

                {toolsMenuOpen && (
                  <nav
                    className="absolute right-0 top-[calc(100%+8px)] w-[min(760px,calc(100vw-32px))] rounded-xl border border-[var(--border)] bg-[var(--bg-card)] p-4 shadow-lg"
                    aria-label={l.allTools}
                  >
                    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                      {AINAUTEN_APPS_BY_CATEGORY.map((group) => (
                        <div key={group.category}>
                          <p className="mb-2 text-[11px] font-bold uppercase tracking-[0.13em] text-[var(--accent)]">
                            {getAinautenAppCategoryLabel(group.category, locale)}
                          </p>
                          <div className="grid gap-1">
                            {group.apps.map((app) => (
                              <a
                                key={app.id}
                                href={app.href}
                                className={
                                  app.id === activeId
                                    ? 'rounded-lg bg-[var(--accent-active-bg)] px-3 py-2 text-sm font-semibold text-[var(--accent-active-fg)]'
                                    : 'rounded-lg px-3 py-2 text-sm font-medium text-[var(--text-secondary)] transition-colors hover:bg-[var(--accent-light)] hover:text-[var(--text-primary)]'
                                }
                                aria-current={app.id === activeId ? 'page' : undefined}
                                onClick={() => setToolsMenuOpen(false)}
                              >
                                {getAinautenAppLabel(app, locale)}
                              </a>
                            ))}
                          </div>
                        </div>
                      ))}
                    </div>
                  </nav>
                )}
              </div>
            )}

            {showThemeToggle && <ThemeToggle locale={locale} />}

            {showLanguageToggle &&
              (onLanguageToggle ? (
                <button
                  type="button"
                  onClick={onLanguageToggle}
                  className={`${controlClass} min-w-[var(--h-control)] px-2 text-xs`}
                  aria-label={locale === 'de' ? 'Sprache auf Englisch wechseln' : 'Switch language to German'}
                >
                  {locale === 'de' ? 'EN' : 'DE'}
                </button>
              ) : (
                <a
                  href={locale === 'de' ? '?lang=en' : '?lang=de'}
                  className={`${controlClass} min-w-[var(--h-control)] px-2 text-xs`}
                >
                  {locale === 'de' ? 'EN' : 'DE'}
                </a>
              ))}

            <button
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
              className="inline-flex h-[var(--h-control)] w-[var(--h-control)] box-border items-center justify-center rounded-lg border border-[var(--border-strong)] text-[var(--text-muted)] transition-all hover:bg-[var(--accent-light)] hover:text-[var(--text-primary)] lg:hidden"
              aria-label={mobileMenuOpen ? l.menuClose : l.menuOpen}
            >
              {mobileMenuOpen ? (
                <X className="h-5 w-5" />
              ) : (
                <Menu className="h-5 w-5" />
              )}
            </button>
          </div>
        </div>

        {mobileMenuOpen && (
          <nav className="border-t border-[var(--border)] py-4 lg:hidden" aria-label="AInauten Apps">
            <div className="grid gap-3">
              {localNav.map((item) => (
                <a
                  key={`${item.href}-${item.label}-mobile`}
                  href={item.href}
                  target={item.external ? '_blank' : undefined}
                  rel={item.external ? 'noopener noreferrer' : undefined}
                  className={
                    item.active
                      ? 'rounded-lg bg-[var(--accent-active-bg)] px-3 py-2 text-sm font-semibold text-[var(--accent-active-fg)]'
                      : 'rounded-lg px-3 py-2 text-sm font-medium text-[var(--text-muted)] hover:bg-[var(--accent-light)] hover:text-[var(--text-primary)]'
                  }
                  aria-current={item.active ? 'page' : undefined}
                  onClick={closeMobileMenu}
                >
                  {item.label}
                </a>
              ))}
              {showGlobalNav &&
                AINAUTEN_APPS_BY_CATEGORY.map((group) => (
                  <div key={`${group.category}-mobile`}>
                    <p className="px-3 pb-1 text-[11px] font-bold uppercase tracking-[0.13em] text-[var(--accent)]">
                      {getAinautenAppCategoryLabel(group.category, locale)}
                    </p>
                    <div className="grid gap-1">
                      {group.apps.map((app) => (
                        <a
                          key={`${app.id}-mobile`}
                          href={app.href}
                          className={
                            app.id === activeId
                              ? 'rounded-lg bg-[var(--accent-active-bg)] px-3 py-2 text-sm font-semibold text-[var(--accent-active-fg)]'
                              : 'rounded-lg px-3 py-2 text-sm font-medium text-[var(--text-muted)] hover:bg-[var(--accent-light)] hover:text-[var(--text-primary)]'
                          }
                          aria-current={app.id === activeId ? 'page' : undefined}
                          onClick={closeMobileMenu}
                        >
                          {getAinautenAppLabel(app, locale)}
                        </a>
                      ))}
                    </div>
                  </div>
                ))}
              <a
                href={AINAUTEN_HOME}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-1 rounded-lg px-3 py-2 text-sm font-medium text-[var(--text-muted)] hover:bg-[var(--accent-light)] hover:text-[var(--text-primary)]"
                onClick={closeMobileMenu}
              >
                {l.mainSite}
                <ArrowUpRight className="h-3 w-3" />
              </a>
            </div>
          </nav>
        )}
      </div>
    </header>
  );
}

export default Header;
