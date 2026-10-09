import React from 'react';
import { Header } from '@ainauten/ui/Header';
import { Footer } from '@ainauten/ui/Footer';

export function VoiceHeader() {
  return <Header product="VOICE" locale="de" logoHref="/" logoSrc="/assets/nauti-logo.png"
    showLanguageToggle={false}
    localNav={[
      { label: 'Video ansehen', href: '#video' },
      { label: 'Installation', href: '#installation' },
      { label: 'Vergleiche', href: '/de/compare/' },
      { label: 'GitHub', href: 'https://github.com/MediaPublishing/ainauten-voice', external: true },
    ]}
    actions={<a className="voice-shell-download" href="#download">Download</a>} />;
}

export function VoiceFooter() {
  return <Footer locale="de" showAppMap showNewsletter={false} />;
}
