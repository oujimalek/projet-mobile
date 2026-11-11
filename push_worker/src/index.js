// M4 - (C4) Notifications push gratuites pour Houmani.
//
// Ce petit programme tourne sur Cloudflare Workers (offre gratuite). Il
// garde la clé du compte de service Firebase (secret SERVICE_ACCOUNT, jamais
// dans le dépôt ni dans l'application) et envoie la notification avec
// Firebase Cloud Messaging (gratuit, même sur l'offre Spark).
//
// L'application appelle POST /notifier avec :
//   { idToken, quartierId, titre, corps, evenementId }
// Le Worker vérifie :
//   1. le jeton Firebase (l'utilisateur est vraiment connecté) ;
//   2. dans Firestore : compte actif, dans CE quartier, leader ou admin ;
// puis envoie à tous les téléphones abonnés au sujet "quartier_{id}".
import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from 'jose';

import { genererPourQuartier, listerQuartiers } from './assistant.js';

const PROJET = 'houmani-235bb';
const CLES_GOOGLE = createRemoteJWKSet(
  new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'),
);

function reponse(statut, objet) {
  return new Response(JSON.stringify(objet), {
    status: statut,
    headers: { 'content-type': 'application/json' },
  });
}

// 1. Le jeton envoyé par l'application : qui est l'utilisateur ?
async function verifierJeton(idToken) {
  const { payload } = await jwtVerify(idToken, CLES_GOOGLE, {
    issuer: `https://securetoken.google.com/${PROJET}`,
    audience: PROJET,
  });
  return payload.sub; // l'uid Firebase
}

// Un jeton d'accès Google à partir du compte de service (valable 1 h)
async function jetonGoogle(compte) {
  const cle = await importPKCS8(compte.private_key, 'RS256');
  const maintenant = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope: 'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging',
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(compte.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt(maintenant)
    .setExpirationTime(maintenant + 3600)
    .sign(cle);
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${assertion}`,
  });
  const donnees = await r.json();
  if (!donnees.access_token) {
    throw new Error('jeton Google refusé');
  }
  return donnees.access_token;
}

// 2. Le profil de l'utilisateur dans Firestore (collection utilisateurs)
async function lireProfil(uid, acces) {
  const r = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJET}/databases/(default)/documents/utilisateurs/${uid}`,
    { headers: { authorization: `Bearer ${acces}` } },
  );
  if (!r.ok) {
    return null;
  }
  const champs = (await r.json()).fields || {};
  return {
    statut: champs.statut?.stringValue,
    role: champs.role?.stringValue,
    quartierId: champs.quartierId?.stringValue,
  };
}

// 3. L'envoi à tout le quartier (sujet FCM)
async function envoyer(acces, quartierId, titre, corps, evenementId, auteurId) {
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${PROJET}/messages:send`, {
    method: 'POST',
    headers: { authorization: `Bearer ${acces}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      message: {
        topic: `quartier_${quartierId}`,
        notification: { title: titre, body: corps },
        data: { evenementId: evenementId || '', auteurId },
        android: { priority: 'high', notification: { channel_id: 'evenements_m4' } },
      },
    }),
  });
  if (!r.ok) {
    console.log('FCM refuse', r.status, (await r.text()).slice(0, 300));
  }
  return r.ok;
}

// Le compte de service (le fichier a parfois un caractère invisible au début)
function lireCompte(env) {
  return JSON.parse(env.SERVICE_ACCOUNT.replace(/^\uFEFF/, ''));
}

// Vérifie l'appelant : jeton Firebase valide ET leader/admin actif de CE
// quartier. Renvoie { uid, acces } ou une Response d'erreur.
async function verifierOrganisateur(env, idToken, quartierId) {
  if (!idToken || !quartierId || !/^[A-Za-z0-9_-]{1,64}$/.test(quartierId)) {
    return reponse(400, { erreur: 'champs manquants' });
  }
  let uid;
  try {
    uid = await verifierJeton(idToken);
  } catch (e) {
    return reponse(401, { erreur: 'non connecté' });
  }
  const acces = await jetonGoogle(lireCompte(env));
  const profil = await lireProfil(uid, acces);
  if (
    !profil ||
    profil.statut !== 'actif' ||
    profil.quartierId !== quartierId ||
    !['leader', 'admin'].includes(profil.role)
  ) {
    return reponse(403, { erreur: 'seuls les leaders et l\'admin du quartier' });
  }
  return { uid, acces };
}

// Notification aux leaders et à l'admin d'un quartier (sujet "leaders_{q}")
async function prevenirLeaders(acces, quartierId, nb) {
  await fetch(`https://fcm.googleapis.com/v1/projects/${PROJET}/messages:send`, {
    method: 'POST',
    headers: { authorization: `Bearer ${acces}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      message: {
        topic: `leaders_${quartierId}`,
        notification: {
          title: 'Assistant du leader',
          body: `${nb} nouvelle${nb > 1 ? 's' : ''} idée${nb > 1 ? 's' : ''} pour ta houma`,
        },
        data: { auteurId: 'assistant' },
        android: { priority: 'high', notification: { channel_id: 'evenements_m4' } },
      },
    }),
  });
}

export default {
  async fetch(requete, env) {
    const chemin = new URL(requete.url).pathname;
    if (requete.method !== 'POST' || !['/notifier', '/suggestions'].includes(chemin)) {
      return reponse(404, { erreur: 'introuvable' });
    }
    let entree;
    try {
      entree = await requete.json();
    } catch (e) {
      return reponse(400, { erreur: 'JSON invalide' });
    }
    try {
      const verif = await verifierOrganisateur(env, entree.idToken, entree.quartierId);
      if (verif instanceof Response) {
        return verif;
      }
      const { uid, acces } = verif;

      // (IA) Les idées de l'assistant pour cette houma, tout de suite
      if (chemin === '/suggestions') {
        const idees = await genererPourQuartier(env, acces, entree.quartierId);
        return reponse(200, { suggestions: idees });
      }

      // (C4) Annonce d'un nouvel événement
      const { quartierId, titre, corps, evenementId } = entree;
      if (!titre || typeof titre !== 'string' || titre.length > 120) {
        return reponse(400, { erreur: 'champs manquants' });
      }
      const ok = await envoyer(acces, quartierId, titre, String(corps || '').slice(0, 200), evenementId, uid);
      return ok ? reponse(200, { envoye: true }) : reponse(502, { erreur: 'envoi FCM refusé' });
    } catch (e) {
      console.log('erreur 500', String(e).slice(0, 200));
      return reponse(500, { erreur: 'erreur serveur' });
    }
  },

  // (IA) Chaque lundi matin : nouvelles idées pour chaque houma + notification
  async scheduled(evenement, env) {
    const acces = await jetonGoogle(lireCompte(env));
    for (const quartierId of await listerQuartiers(acces)) {
      try {
        const idees = await genererPourQuartier(env, acces, quartierId);
        if (idees.length > 0) {
          await prevenirLeaders(acces, quartierId, idees.length);
        }
      } catch (e) {
        console.log('assistant', quartierId, String(e).slice(0, 200));
      }
    }
  },
};
