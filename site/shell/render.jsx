import React from 'react';
import { renderToString } from 'react-dom/server';
import { VoiceHeader, VoiceFooter } from './components.jsx';

console.log(JSON.stringify({ header: renderToString(<VoiceHeader />), footer: renderToString(<VoiceFooter />) }));
