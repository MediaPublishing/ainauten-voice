import React from 'react';
import { hydrateRoot } from 'react-dom/client';
import { VoiceHeader, VoiceFooter } from './components.jsx';

hydrateRoot(document.querySelector('#ainauten-header'), <VoiceHeader />);
hydrateRoot(document.querySelector('#ainauten-footer'), <VoiceFooter />);
