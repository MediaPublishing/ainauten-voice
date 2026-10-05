// The public site only forwards reporting routes to the private Worker.
// Credentials and report storage remain in that Worker, never in Pages assets.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    // Retire the old installer even when an edge still caches its asset.
    if (url.pathname === '/downloads/AInauten-Voice-0.1.1-arm64.dmg') {
      const metadataURL = new URL('/downloads/release.json', url.origin);
      const response = await env.ASSETS.fetch(new Request(metadataURL));
      const metadata = response.ok ? await response.json() : null;
      if (metadata && /^AInauten-Voice-[0-9.]+-arm64\.dmg$/.test(metadata.filename) && metadata.filename !== 'AInauten-Voice-0.1.1-arm64.dmg') {
        return new Response(null, {status:302, headers:{Location:new URL('/downloads/' + metadata.filename, url.origin).href, 'Cache-Control':'no-store'}});
      }
      return new Response('Dieser alte Download wurde zurückgezogen.', {status:410, headers:{'Cache-Control':'no-store'}});
    }
    const reporting = /^\/api\/reports(?:\/|$)/.test(url.pathname) || /^\/api\/operator\/reports(?:\/|$)/.test(url.pathname);
    if (!reporting) return env.ASSETS.fetch(request);
    if (url.hostname !== 'voice.ainauten.com' || !env.REPORTING) {
      return new Response(JSON.stringify({error:'not_active'}), {status:503, headers:{'Content-Type':'application/json', 'Cache-Control':'no-store'}});
    }
    return env.REPORTING.fetch(request);
  }
};
