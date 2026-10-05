module.exports = {
  content: ['./vendor/ainauten-ui/src/**/*.{ts,tsx}', './shell/*.jsx'],
  important: ':is(#ainauten-header, #ainauten-footer)',
  corePlugins: { preflight: false },
  theme: { extend: { fontFamily: { sans: ['Inter', 'system-ui', 'sans-serif'] } } },
};
