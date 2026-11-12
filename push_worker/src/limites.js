// Limite d'appels par utilisateur, par route et par jour (heure de Tunis).
//
// Sans limite, un seul compte pourrait appeler l'IA en boucle et épuiser
// le quota gratuit de Workers AI pour toute l'application, ou envoyer des
// notifications sans fin à tout un quartier.
//
// Les compteurs sont dans Cloudflare KV (offre gratuite), binding LIMITES
// (voir wrangler.toml). Clé : "route:uid:AAAA-MM-JJ", effacée par KV
// après 2 jours. KV n'est pas transactionnel : deux appels exactement
// simultanés peuvent compter pour un, ce qui suffit pour un garde-fou.
// Seuls les appels ACCEPTÉS écrivent dans KV (offre gratuite : 1 000
// écritures par jour) ; un appel refusé ne fait qu'une lecture.

export const LIMITES_PAR_JOUR = {
  '/ameliorer': 20,
  '/correspondances': 20,
  '/notifier': 10,
  '/suggestions': 5,
};

const MESSAGES = {
  '/ameliorer': (n) => `Tu as utilisé l'IA ${n} fois aujourd'hui pour tes annonces : c'est la limite. Réessaie demain.`,
  '/correspondances': (n) => `Tu as fait ${n} recherches avec l'IA aujourd'hui : c'est la limite. Réessaie demain.`,
  '/notifier': (n) => `Ton quartier a déjà reçu ${n} annonces de ta part aujourd'hui : c'est la limite. Réessaie demain.`,
  '/suggestions': (n) => `Tu as demandé ${n} fois des idées aujourd'hui : c'est la limite. Réessaie demain.`,
};

// Le jour en Tunisie (UTC+1, pas d'heure d'été) : AAAA-MM-JJ
export function jourTunisie(maintenant) {
  return new Date(maintenant.getTime() + 3600 * 1000).toISOString().slice(0, 10);
}

export function cleLimite(chemin, uid, maintenant) {
  return `${chemin}:${uid}:${jourTunisie(maintenant)}`;
}

/// Compte cet appel. Renvoie { ok: true } ou { ok: false, message }.
/// Sans KV (binding absent) ou si KV échoue : l'appel passe (on ne bloque
/// pas l'application à cause du garde-fou), avec une ligne dans le journal.
export async function compterAppel(kv, chemin, uid, maintenant = new Date()) {
  const max = LIMITES_PAR_JOUR[chemin];
  if (!max) {
    return { ok: true };
  }
  if (!kv) {
    console.log('limites : binding LIMITES absent, pas de limite');
    return { ok: true };
  }
  const cle = cleLimite(chemin, uid, maintenant);
  try {
    const deja = Number(await kv.get(cle)) || 0;
    if (deja >= max) {
      return { ok: false, message: MESSAGES[chemin](max) };
    }
    await kv.put(cle, String(deja + 1), { expirationTtl: 2 * 86400 });
    return { ok: true };
  } catch (e) {
    console.log('limites : KV indisponible', String(e).slice(0, 200));
    return { ok: true };
  }
}
