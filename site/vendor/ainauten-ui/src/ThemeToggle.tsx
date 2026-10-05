'use client';

import { useState, useEffect } from 'react';
import { Moon, Sun, Monitor } from 'lucide-react';
import type { ThemeToggleProps, Locale } from './types';

type Theme = 'light' | 'dark' | 'system';

const labels: Record<Locale, {
  light: string;
  dark: string;
  system: string;
  toggleTheme: string;
}> = {
  de: {
    light: 'Hell',
    dark: 'Dunkel',
    system: 'System',
    toggleTheme: 'Theme wechseln',
  },
  en: {
    light: 'Light',
    dark: 'Dark',
    system: 'System',
    toggleTheme: 'Toggle theme',
  },
};

/**
 * AInauten Theme Toggle Component
 *
 * A simple button to toggle between light, dark, and system themes.
 * Persists preference to localStorage and syncs with system preference.
 */
export function ThemeToggle({
  locale = 'de',
  className = '',
}: ThemeToggleProps) {
  const [theme, setTheme] = useState<Theme>('system');
  const [mounted, setMounted] = useState(false);
  const l = labels[locale];
  const buttonClass =
    `inline-flex h-[var(--h-control)] w-[var(--h-control)] box-border items-center justify-center rounded-lg border border-[var(--border-strong)] bg-[var(--bg-secondary)] text-[var(--text-muted)] transition-colors hover:bg-[var(--accent-light)] hover:text-[var(--text-primary)] ${className}`;

  // Only run on client
  useEffect(() => {
    setMounted(true);
    const saved = localStorage.getItem('theme') as Theme | null;
    if (saved) {
      setTheme(saved);
    }
  }, []);

  useEffect(() => {
    if (!mounted) return;

    const root = document.documentElement;
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;

    if (theme === 'dark' || (theme === 'system' && prefersDark)) {
      root.classList.add('dark');
    } else {
      root.classList.remove('dark');
    }

    if (theme !== 'system') {
      localStorage.setItem('theme', theme);
    } else {
      localStorage.removeItem('theme');
    }
  }, [theme, mounted]);

  // Listen for system preference changes
  useEffect(() => {
    if (!mounted || theme !== 'system') return;

    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = (e: MediaQueryListEvent) => {
      const root = document.documentElement;
      if (e.matches) {
        root.classList.add('dark');
      } else {
        root.classList.remove('dark');
      }
    };

    mediaQuery.addEventListener('change', handler);
    return () => mediaQuery.removeEventListener('change', handler);
  }, [theme, mounted]);

  const cycleTheme = () => {
    const next: Record<Theme, Theme> = {
      light: 'dark',
      dark: 'system',
      system: 'light',
    };
    setTheme(next[theme]);
  };

  // Prevent hydration mismatch
  if (!mounted) {
    return (
      <button
        className={buttonClass}
        aria-label={l.toggleTheme}
      >
        <Sun className="h-4 w-4" />
      </button>
    );
  }

  const Icon = theme === 'light' ? Sun : theme === 'dark' ? Moon : Monitor;
  const label = theme === 'light' ? l.light : theme === 'dark' ? l.dark : l.system;

  return (
    <button
      onClick={cycleTheme}
      className={buttonClass}
      aria-label={`${l.toggleTheme}: ${label}`}
      title={label}
    >
      <Icon className="h-4 w-4" />
    </button>
  );
}

export default ThemeToggle;
