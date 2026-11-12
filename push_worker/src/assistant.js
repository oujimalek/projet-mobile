// M4 - (IA) L'assistant du leader : des idées d'événements et de sondages
// pour UNE houma, à partir de ses données (ANONYMES : aucun nom n'est
// envoyé à l'IA) et du calendrier. IA gratuite : Cloudflare Workers AI.
//
// Résultat rangé dans quartiers/{q}/suggestionsIA/courant ; l'application
// le lit (seuls les leaders et l'admin, voir firestore.rules).

const PROJET = 'houmani-235bb';
const DOCS = `https://firestore.googleapis.com/v1/projects/${PROJET}/databases/(default)/documents`;
// Modèle gratuit de Workers AI (si Cloudflare le retire un jour, choisir un
// autre modèle « Text Generation » : npx wrangler ai models list)
const MODELE = '@cf/mistralai/mistral-small-3.1-24b-instruct';
const CATEGORIES = ['fete', 'reunion', 'nettoyage', 'sport', 'culture', 'autre'];

// ---------- Lecture Firestore (REST, compte de service) ----------

function valeur(champ) {
  if (!champ) return null;
  if ('stringValue' in champ) return champ.stringValue;
  if ('integerValue' in champ) return Number(champ.integerValue);
  if ('doubleValue' in champ) return champ.doubleValue;
  if ('booleanValue' in champ) return champ.booleanValue;
  if ('timestampValue' in champ) return new Date(champ.timestampValue);
  if ('arrayValue' in champ) return (champ.arrayValue.values || []).map(valeur);
  return null;
}

async function lister(acces, chemin) {
  const r = await fetch(`${DOCS}/${chemin}?pageSize=300`, {
    headers: { authorization: `Bearer ${acces}` },
  });
  if (!r.ok) return [];
  const docs = (await r.json()).documents || [];
  return docs.map((d) => {
    const objet = { id: d.name.split('/').pop() };
    for (const [cle, champ] of Object.entries(d.fields || {})) objet[cle] = valeur(champ);
    return objet;
  });
}

async function compterMembres(acces, quartierId) {
  const r = await fetch(`${DOCS}:runAggregationQuery`, {
    method: 'POST',
    headers: { authorization: `Bearer ${acces}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      structuredAggregationQuery: {
        aggregations: [{ alias: 'n', count: {} }],
        structuredQuery: {
          from: [{ collectionId: 'utilisateurs' }],
          where: {
            compositeFilter: {
              op: 'AND',
              filters: [
                { fieldFilter: { field: { fieldPath: 'quartierId' }, op: 'EQUAL', value: { stringValue: quartierId } } },
                { fieldFilter: { field: { fieldPath: 'statut' }, op: 'EQUAL', value: { stringValue: 'actif' } } },
              ],
            },
          },
        },
      },
    }),
  });
  if (!r.ok) return 0;
  const rep = await r.json();
  return Number(rep[0]?.result?.aggregateFields?.n?.integerValue || 0);
}

// ---------- Les statistiques ANONYMES de la houma ----------

const JOURS = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'];

// Heure de Tunis (UTC+1, pas d'heure d'été)
function enTunisie(date) {
  return new Date(date.getTime() + 3600 * 1000);
}

export function statistiques(evenements, sondages, services, nbMembres, maintenant) {
  const passes = evenements.filter((e) => e.date && e.date < maintenant && !e.annule);
  const aVenir = evenements.filter((e) => e.date && e.date >= maintenant && !e.annule);

  // (3) Meilleur moment : moyenne d'inscrits par créneau
  const parCreneau = {};
  for (const e of passes) {
    const d = enTunisie(e.date);
    const h = d.getUTCHours();
    const creneau = `${JOURS[d.getUTCDay()]} ${h < 12 ? 'matin' : h < 17 ? 'après-midi' : 'soir'}`;
    parCreneau[creneau] = parCreneau[creneau] || { total: 0, nb: 0 };
    parCreneau[creneau].total += e.nbParticipants || 0;
    parCreneau[creneau].nb += 1;
  }
  const creneaux = Object.entries(parCreneau)
    .map(([nom, s]) => ({ nom, moyenne: Math.round((s.total / s.nb) * 10) / 10, nb: s.nb }))
    .sort((a, b) => b.moyenne - a.moyenne);

  // Par catégorie : nombre, moyenne d'inscrits, dernier événement
  const parCategorie = {};
  for (const c of CATEGORIES) parCategorie[c] = { nb: 0, inscrits: 0, dernier: null };
  for (const e of passes) {
    const c = parCategorie[e.categorie] || parCategorie.autre;
    c.nb += 1;
    c.inscrits += e.nbParticipants || 0;
    if (!c.dernier || e.date > c.dernier) c.dernier = e.date;
  }
  const categories = Object.entries(parCategorie).map(([nom, c]) => ({
    nom,
    nb: c.nb,
    moyenneInscrits: c.nb ? Math.round((c.inscrits / c.nb) * 10) / 10 : 0,
    joursDepuisDernier: c.dernier ? Math.round((maintenant - c.dernier) / 86400000) : null,
  }));

  return {
    nbMembres,
    nbEvenementsPasses: passes.length,
    evenementsAVenir: aVenir.map((e) => ({ titre: e.titre, categorie: e.categorie, date: e.date.toISOString().slice(0, 10) })),
    categories,
    meilleursCreneaux: creneaux.slice(0, 3),
    sondagesRecents: sondages.slice(0, 5).map((s) => ({ question: s.question })),
    servicesCommuns: services.filter((s) => s.estCommun).map((s) => ({ titre: s.titre, jour: s.jour })),
  };
}

// ---------- (5) Le calendrier : saison et fêtes ----------

// Dates approximatives (calendrier lunaire) : 2026-2027
const FETES = [
  { nom: 'Ramadan', debut: '2027-02-08', fin: '2027-03-09' },
  { nom: 'Aïd el-Fitr', debut: '2027-03-10', fin: '2027-03-11' },
  { nom: 'Aïd el-Adha', debut: '2026-05-27', fin: '2026-05-28' },
  { nom: 'Aïd el-Adha', debut: '2027-05-16', fin: '2027-05-17' },
  { nom: 'Mouled', debut: '2026-08-25', fin: '2026-08-25' },
  { nom: 'Nouvel an', debut: '2027-01-01', fin: '2027-01-01' },
  { nom: 'Vacances d\'hiver', debut: '2026-12-20', fin: '2027-01-03' },
  { nom: 'Vacances de printemps', debut: '2027-03-15', fin: '2027-03-28' },
  { nom: 'Vacances d\'été', debut: '2027-07-01', fin: '2027-09-14' },
];

export function calendrier(maintenant) {
  const mois = maintenant.getUTCMonth() + 1;
  const saison = mois <= 2 || mois === 12 ? 'hiver' : mois <= 5 ? 'printemps' : mois <= 8 ? 'été' : 'automne';
  const dans45j = new Date(maintenant.getTime() + 45 * 86400000);
  const prochaines = FETES.filter((f) => new Date(f.fin) >= maintenant && new Date(f.debut) <= dans45j)
    .map((f) => `${f.nom} (à partir du ${f.debut})`);
  return { aujourdhui: maintenant.toISOString().slice(0, 10), jour: JOURS[enTunisie(maintenant).getUTCDay()], saison, prochainesFetes: prochaines };
}

// ---------- L'IA ----------

function consigne(stats, cal) {
  return `Tu es l'assistant des leaders d'une résidence (houma) en Tunisie, dans l'application Houmani.
Voici les données ANONYMES de la houma (JSON) :
${JSON.stringify(stats)}
Calendrier : ${JSON.stringify(cal)}

Propose 3 à 5 idées utiles et concrètes POUR CETTE HOUMA, en français simple :
- des événements à organiser (catégories possibles : ${CATEGORIES.join(', ')}) ;
- des sondages quand l'avis des voisins n'est pas clair ;
- au plus 1 conseil (meilleur moment, participation...).
Appuie-toi sur les chiffres (catégories peu faites depuis longtemps, créneaux qui marchent, fêtes qui arrivent, saison).
Les dates proposées sont dans les 30 prochains jours, après le ${cal.aujourdhui}. Ne propose pas un événement déjà prévu.

Réponds UNIQUEMENT avec un tableau JSON, sans texte autour, de la forme :
[{"type":"evenement","titre":"...","categorie":"nettoyage","date":"AAAA-MM-JJ","heure":"18:00","raison":"..."},
 {"type":"sondage","question":"...","choix":["...","..."],"raison":"..."},
 {"type":"conseil","titre":"...","raison":"..."}]
"raison" : une phrase courte qui cite les données. Pas de noms de personnes.`;
}

// Garde seulement des idées propres (l'IA peut se tromper de format)
export function nettoyer(texte, maintenant) {
  const debut = texte.indexOf('[');
  const fin = texte.lastIndexOf(']');
  if (debut < 0 || fin <= debut) return [];
  let liste;
  try {
    liste = JSON.parse(texte.slice(debut, fin + 1));
  } catch (e) {
    return [];
  }
  const propres = [];
  for (const s of Array.isArray(liste) ? liste : []) {
    if (!s || typeof s !== 'object') continue;
    const raison = String(s.raison || '').slice(0, 220);
    if (s.type === 'evenement' && s.titre) {
      let date = /^\d{4}-\d{2}-\d{2}$/.test(s.date || '') ? s.date : null;
      if (date && new Date(date) < maintenant) date = null;
      propres.push({
        type: 'evenement',
        titre: String(s.titre).slice(0, 80),
        categorie: CATEGORIES.includes(s.categorie) ? s.categorie : 'autre',
        date,
        heure: /^\d{1,2}:\d{2}$/.test(s.heure || '') ? s.heure : '18:00',
        raison,
      });
    } else if (s.type === 'sondage' && s.question && Array.isArray(s.choix) && s.choix.length >= 2) {
      propres.push({
        type: 'sondage',
        question: String(s.question).slice(0, 120),
        choix: s.choix.slice(0, 6).map((c) => String(c).slice(0, 40)),
        raison,
      });
    } else if (s.type === 'conseil' && s.titre) {
      propres.push({ type: 'conseil', titre: String(s.titre).slice(0, 100), raison });
    }
    if (propres.length >= 5) break;
  }
  return propres;
}

// ---------- Écriture du résultat ----------

function versFirestore(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(versFirestore) } };
  if (typeof v === 'object') {
    const fields = {};
    for (const [k, x] of Object.entries(v)) fields[k] = versFirestore(x);
    return { mapValue: { fields } };
  }
  return { stringValue: String(v) };
}

async function enregistrer(acces, quartierId, suggestions, maintenant) {
  await fetch(`${DOCS}/quartiers/${quartierId}/suggestionsIA/courant`, {
    method: 'PATCH',
    headers: { authorization: `Bearer ${acces}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      fields: {
        date: { timestampValue: maintenant.toISOString() },
        suggestions: versFirestore(suggestions),
      },
    }),
  });
}

/// Analyse UNE houma et enregistre ses idées. Renvoie les idées.
export async function genererPourQuartier(env, acces, quartierId) {
  const maintenant = new Date();
  const base = `quartiers/${quartierId}`;
  const [evenements, sondages, services, nbMembres] = await Promise.all([
    lister(acces, `${base}/evenements`),
    lister(acces, `${base}/sondages`),
    lister(acces, `${base}/services`),
    compterMembres(acces, quartierId),
  ]);
  const stats = statistiques(evenements, sondages, services, nbMembres, maintenant);
  const cal = calendrier(maintenant);
  const reponse = await env.AI.run(MODELE, {
    messages: [{ role: 'user', content: consigne(stats, cal) }],
    max_tokens: 900,
    temperature: 0.7,
  });
  // Selon le modèle : { response } ou { choices: [{ message: { content } }] }
  const texte = typeof reponse?.response === 'string'
    ? reponse.response
    : (reponse?.choices?.[0]?.message?.content ?? JSON.stringify(reponse?.response ?? ''));
  const suggestions = nettoyer(String(texte), maintenant);
  if (suggestions.length === 0) {
    console.log('IA illisible');
  }
  if (suggestions.length > 0) {
    await enregistrer(acces, quartierId, suggestions, maintenant);
  }
  return suggestions;
}

/// Tous les quartiers (pour l'analyse automatique de la semaine).
export async function listerQuartiers(acces) {
  const quartiers = await lister(acces, 'quartiers');
  return quartiers.map((q) => q.id);
}
