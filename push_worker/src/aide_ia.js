// M1 / M2 - (IA) Deux petites aides pour tous les résidents actifs.
// IA gratuite : Cloudflare Workers AI (même modèle que l'assistant M4).
// Aucun nom ni identifiant de personne n'est envoyé à l'IA.
//
//  - /ameliorer (M2) : réécrit le titre et la description d'une annonce
//    de service pour qu'elle soit claire et polie ;
//  - /correspondances (M1) : à partir d'un besoin ("ma machine à laver
//    fuit"), choisit dans la LISTE des compétences de la houma celles qui
//    peuvent aider. L'application retrouve ensuite les voisins elle-même.

const MODELE = '@cf/mistralai/mistral-small-3.1-24b-instruct';

// Le texte de la réponse, quel que soit le format du modèle
function texteDe(reponse) {
  if (typeof reponse?.response === 'string') return reponse.response;
  return reponse?.choices?.[0]?.message?.content ?? JSON.stringify(reponse?.response ?? '');
}

// Le premier objet / tableau JSON trouvé dans le texte (null sinon)
function extraire(texte, ouvrant, fermant) {
  const debut = texte.indexOf(ouvrant);
  const fin = texte.lastIndexOf(fermant);
  if (debut < 0 || fin <= debut) return null;
  try {
    return JSON.parse(texte.slice(debut, fin + 1));
  } catch (e) {
    return null;
  }
}

// ---------- (M2) Améliorer une annonce ----------

export function consigneAmelioration(titre, description, categorie) {
  return `Tu aides un voisin à écrire une annonce de service dans l'application Houmani (entraide entre voisins d'une résidence en Tunisie).
Catégorie : ${categorie || 'autre'}
Titre écrit par le voisin : ${JSON.stringify(titre)}
Description écrite par le voisin : ${JSON.stringify(description)}

Réécris l'annonce en français simple, clair et poli :
- garde EXACTEMENT le sens, les prix, les horaires et les détails donnés ; n'invente rien ;
- titre court (60 caractères au plus) ;
- description de 2 à 4 phrases (400 caractères au plus) ;
- pas de nom de personne, pas de numéro de téléphone, pas d'émoji.

Réponds UNIQUEMENT avec un objet JSON, sans texte autour :
{"titre":"...","description":"..."}`;
}

export function nettoyerAmelioration(texte) {
  const objet = extraire(String(texte), '{', '}');
  if (!objet || typeof objet !== 'object') return null;
  const titre = String(objet.titre || '').trim().slice(0, 60);
  const description = String(objet.description || '').trim().slice(0, 400);
  if (titre.length < 3 || description.length < 10) return null;
  return { titre, description };
}

export async function ameliorerAnnonce(env, titre, description, categorie) {
  const reponse = await env.AI.run(MODELE, {
    messages: [{ role: 'user', content: consigneAmelioration(titre, description, categorie) }],
    max_tokens: 400,
    temperature: 0.4,
  });
  return nettoyerAmelioration(texteDe(reponse));
}

// ---------- (M1) Compétences utiles pour un besoin ----------

export function consigneCorrespondances(besoin, competences) {
  return `Dans une résidence en Tunisie, un voisin a ce besoin : ${JSON.stringify(besoin)}
Voici les compétences déclarées par les voisins de la résidence (liste JSON) :
${JSON.stringify(competences)}

Choisis dans CETTE LISTE (orthographe exacte) au plus 3 compétences qui peuvent aider, de la plus utile à la moins utile.
Si aucune ne convient, réponds [].
Réponds UNIQUEMENT avec un tableau JSON, sans texte autour :
[{"competence":"...","raison":"une phrase courte"}]`;
}

// Garde seulement des compétences de la liste (l'IA peut en inventer)
export function nettoyerCorrespondances(texte, competences) {
  const liste = extraire(String(texte), '[', ']');
  if (!Array.isArray(liste)) return [];
  const parMinuscule = new Map(competences.map((c) => [c.toLowerCase(), c]));
  const propres = [];
  for (const un of liste) {
    const exacte = parMinuscule.get(String(un?.competence || '').trim().toLowerCase());
    if (!exacte || propres.some((p) => p.competence === exacte)) continue;
    propres.push({ competence: exacte, raison: String(un.raison || '').slice(0, 160) });
    if (propres.length >= 3) break;
  }
  return propres;
}

export async function trouverCompetences(env, besoin, competences) {
  const reponse = await env.AI.run(MODELE, {
    messages: [{ role: 'user', content: consigneCorrespondances(besoin, competences) }],
    max_tokens: 300,
    temperature: 0.2,
  });
  return nettoyerCorrespondances(texteDe(reponse), competences);
}
