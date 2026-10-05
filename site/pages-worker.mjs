// The public site only forwards reporting routes to the private Worker.
// Credentials and report storage remain in that Worker, never in Pages assets.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const reporting = /^\/api\/reports(?:\/|$)/.test(url.pathname) || /^\/api\/operator\/reports(?:\/|$)/.test(url.pathname);
    if (!reporting) return env.ASSETS.fetch(request);
    if (url.hostname !== 'voice.ainauten.com' || !env.REPORTING) {
      return new Response(JSON.stringify({error:'not_active'}), {status:503, headers:{'Content-Type':'application/json', 'Cache-Control':'no-store'}});
    }
    return env.REPORTING.fetch(request);
  }
};
