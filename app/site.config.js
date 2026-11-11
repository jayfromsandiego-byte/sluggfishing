/**
 * Slugg Fishing — template config
 *
 * This is the place to rebrand the web preview for another small fishing
 * or outdoor business. When the page runs, these values override the
 * matching fallbacks in app/index.html (wordmark, colors, demo profile,
 * map center, and outbound links).
 *
 * Change this file. Leave the San Diego spots, waypoints, species notes,
 * and regulation summaries in app/index.html until you are ready to
 * replace that content for a different region. Those arrays are data,
 * not brand chrome.
 *
 * Do not put service-role keys, passwords, or private contact details here.
 * supabaseAnonKey is the public client key only, and it ships empty.
 *
 * The on-screen wordmark below is the working title already in the UI
 * ("First Light"). The project name is Slugg Fishing.
 */
window.SITE = {
  communityName: 'Slugg Fishing',

  brand: {
    wordmarkLead: 'First',
    wordmarkTail: 'Light',
    wordmarkTailColor: '#CFE0F5',
    documentTitle: 'First Light — San Diego Fishing (working title)',
    description: 'First Light (working title) — San Diego fishing preview for the Slugg Fishing project. Sample spots and reports, with live weather where the screen says so.'
  },

  /**
   * Colors match the preview's existing palette. Keys are CSS custom
   * properties (--bg, --blue, and so on) applied on <html> before paint.
   * app/index.html keeps the same values in :root as a no-JavaScript fallback.
   */
  theme: {
    'bg': '#060D1A',
    'surface': '#0B1728',
    'card': '#10203A',
    'card-2': '#142A4D',
    'raised': '#1A3159',
    'line': 'rgba(148,178,224,.14)',
    'line-2': 'rgba(148,178,224,.22)',
    'text': '#F4F7FC',
    'sub': '#8FA3C4',
    'faint': '#5E7398',
    'blue': '#2F7BF6',
    'blue-2': '#4D93FF',
    'green': '#2FA362',
    'red': '#E5484D',
    'orange': '#F5A623',
    'star': '#F7C948',
    'teal': '#37B3C8',
    'violet': '#7C5CFF',
    'font': "'Inter',-apple-system,system-ui,sans-serif"
  },

  place: {
    regionName: 'San Diego',
    /** Shown on the Conditions header, next to today's date. */
    conditionsLabel: 'Point Loma',
    /** Distances in the waypoint list are measured from this point. */
    distanceOrigin: { lat: 32.672, lon: -117.240 },
    mapCenter: { lat: 32.62, lon: -117.55, zoom: 8 },
    /**
     * Placeholder copy on the profile row. The preview does not download
     * a map pack, and 146 MB is not a measured file size.
     */
    offlinePackNote: 'San Diego pack · 146 MB · never lapses mid-trip',
    /**
     * Obvious demo profile. Counts start at 0. They are not a user base.
     */
    demoProfile: {
      name: 'Demo Angler',
      homePort: 'San Diego, CA',
      catches: 0,
      spots: 0,
      followers: 0,
      following: 0
    }
  },

  links: {
    cdfwOceanSouth: 'https://wildlife.ca.gov/Fishing/Ocean/Regulations/Fishing-Map/Southern',
    cdfwMpas: 'https://wildlife.ca.gov/Conservation/Marine/MPAs',
    cdfwFishPlants: 'https://wildlife.ca.gov/Fishing/Inland/Fish-Plants',
    cdfwCaltip: 'https://wildlife.ca.gov/Enforcement/CalTIP',
    conapescaSport: 'https://www.gob.mx/conapesca/documentos/conapesca-01-016-pesca-deportivo-recreativa',
    mexicoEntry: 'https://travel.state.gov/en/international-travel/travel-advisories/mexico.html',
    noaaWestCoastRec: 'https://www.fisheries.noaa.gov/west-coast/recreational-fishing/recreational-fisheries-west-coast',
    noaaBluefin: 'https://www.fisheries.noaa.gov/species/pacific-bluefin-tuna',
    /** Shore spots append latitude,longitude and open this URL. */
    mapsSearchPrefix: 'https://www.google.com/maps/search/?api=1&query='
  },

  /**
   * mode 'mock' keeps reports in the browser.
   * mode 'supabase' posts to the RPCs described in supabase/migrations/.
   * No cloud project is configured in this repository.
   */
  backend: {
    mode: 'mock',
    supabaseUrl: '',
    supabaseAnonKey: ''
  }
};
