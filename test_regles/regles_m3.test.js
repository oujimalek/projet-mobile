// Tests des règles Firestore du Module 3 (signalements et confirmations).
//
// Ils tournent sur l'ÉMULATEUR Firestore (projet "demo-houmani", jamais le
// vrai projet). Lancer depuis la racine du dépôt :
//   firebase emulators:exec --only firestore --project demo-houmani "npm --prefix test_regles test"
//
// assertSucceeds : la règle doit AUTORISER l'opération.
// assertFails    : la règle doit la REFUSER.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  deleteField,
  doc,
  GeoPoint,
  getDoc,
  increment,
  setDoc,
  Timestamp,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

let env;

function membre(prenom, quartierId, statut, role = 'resident') {
  return {
    prenom,
    nom: 'Test',
    email: `${prenom.toLowerCase()}@houmani.tn`,
    telephone: '',
    quartierId,
    quartierNom: 'El Yasmine',
    residence: 'El Yasmine',
    logement: '',
    statut,
    role,
    competences: [],
    avatar: '',
    dateDemande: Timestamp.fromDate(new Date('2026-10-01')),
  };
}

// La base vue par un utilisateur connecté (uid + jeton)
function base(uid) {
  return env
    .authenticatedContext(uid, { email: `${uid}@houmani.tn`, email_verified: true })
    .firestore();
}

const PHOTO =
  'https://res.cloudinary.com/pu3lxdrf/image/upload/v1/houmani/signalements/abc.jpg';

// Un signalement comme celui que l'app écrit (Signalement.toMap)
function signalement(auteurId, extra = {}) {
  return {
    titre: 'Fuite d\'eau',
    description: 'Une canalisation fuit devant le bloc A',
    categorieId: 'eau',
    statut: 'enAttente',
    date: Timestamp.fromDate(new Date('2026-11-01T10:00:00')),
    lieu: 'Bloc A',
    auteurId,
    auteurNom: 'Youssef T.',
    nbConfirmations: 0,
    danger: false,
    ...extra,
  };
}

const S = 'quartiers/q1/signalements';

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-houmani',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});

after(async () => {
  await env.cleanup();
});

// Avant chaque test : base vide, puis les données de départ (sans les règles)
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (contexte) => {
    const db = contexte.firestore();
    await setDoc(doc(db, 'quartiers/q1'), { nom: 'El Yasmine', localisation: 'Ennasr 2' });
    await setDoc(doc(db, 'quartiers/q2'), { nom: 'El Wafa', localisation: 'Ennasr 1' });
    await setDoc(doc(db, 'utilisateurs/admin1'), membre('Amira', 'q1', 'actif', 'admin'));
    await setDoc(doc(db, 'utilisateurs/resident1'), membre('Youssef', 'q1', 'actif'));
    await setDoc(doc(db, 'utilisateurs/resident2'), membre('Sarra', 'q1', 'actif'));
    await setDoc(doc(db, 'utilisateurs/attente1'), membre('Hedi', 'q1', 'enAttente'));
    await setDoc(doc(db, 'utilisateurs/autre1'), membre('Karim', 'q2', 'actif'));
    // Les signalements de Youssef, dans chaque statut
    await setDoc(doc(db, `${S}/attente`), signalement('resident1'));
    await setDoc(doc(db, `${S}/encours`), signalement('resident1', { statut: 'enCours' }));
    await setDoc(doc(db, `${S}/resolu`), signalement('resident1', { statut: 'resolu' }));
    await setDoc(doc(db, `${S}/refuse`), signalement('resident1', { statut: 'refuse' }));
    await setDoc(doc(db, `${S}/avecphoto`), signalement('resident1', {
      photoUrl: PHOTO,
      position: new GeoPoint(36.8625, 10.17),
    }));
  });
});

/// Confirme comme l'app : la fiche ET le compteur dans le même WriteBatch.
function confirmer(uid, id) {
  const db = base(uid);
  const batch = writeBatch(db);
  batch.set(doc(db, `${S}/${id}/confirmations/${uid}`), { date: Timestamp.now() });
  batch.update(doc(db, `${S}/${id}`), { nbConfirmations: increment(1) });
  return batch.commit();
}

// ---------------------------------------------------------------------
describe('lire', () => {
  test('un membre actif du quartier lit les signalements', async () => {
    await assertSucceeds(getDoc(doc(base('resident2'), `${S}/attente`)));
  });

  test('un membre en attente ou d\'un autre quartier, non', async () => {
    await assertFails(getDoc(doc(base('attente1'), `${S}/attente`)));
    await assertFails(getDoc(doc(base('autre1'), `${S}/attente`)));
  });
});

// ---------------------------------------------------------------------
describe('créer un signalement', () => {
  test('un résident crée un signalement simple', async () => {
    await assertSucceeds(setDoc(doc(base('resident2'), `${S}/n1`), signalement('resident2')));
  });

  test('avec danger, position et photo de notre Cloudinary', async () => {
    await assertSucceeds(setDoc(doc(base('resident2'), `${S}/n1`), signalement('resident2', {
      danger: true,
      position: new GeoPoint(36.86, 10.17),
      photoUrl: PHOTO,
    })));
  });

  test('pas au nom d\'un autre, ni par un membre en attente', async () => {
    await assertFails(setDoc(doc(base('resident2'), `${S}/n1`), signalement('resident1')));
    await assertFails(setDoc(doc(base('attente1'), `${S}/n1`), signalement('attente1')));
    await assertFails(setDoc(doc(base('autre1'), `${S}/n1`), signalement('autre1')));
  });

  test('toujours en attente, sans confirmation', async () => {
    const db = base('resident2');
    await assertFails(setDoc(doc(db, `${S}/n1`), signalement('resident2', { statut: 'resolu' })));
    await assertFails(setDoc(doc(db, `${S}/n1`), signalement('resident2', { nbConfirmations: 5 })));
  });

  test('aucun champ inconnu', async () => {
    await assertFails(setDoc(doc(base('resident2'), `${S}/n1`),
      signalement('resident2', { prioritaire: true })));
  });

  test('catégorie connue, titre de 3 à 80 caractères, description et lieu', async () => {
    const db = base('resident2');
    await assertFails(setDoc(doc(db, `${S}/n1`), signalement('resident2', { categorieId: 'piscine' })));
    await assertFails(setDoc(doc(db, `${S}/n1`), signalement('resident2', { titre: 'ab' })));
    await assertFails(setDoc(doc(db, `${S}/n1`), signalement('resident2', { titre: 'a'.repeat(81) })));
    await assertFails(setDoc(doc(db, `${S}/n1`), signalement('resident2', { description: 'court' })));
    await assertFails(setDoc(doc(db, `${S}/n1`), signalement('resident2', { lieu: 'A' })));
    await assertFails(setDoc(doc(db, `${S}/n1`), signalement('resident2', { date: '2026-11-01' })));
  });

  test('la photo doit venir de NOTRE compte Cloudinary, en https', async () => {
    const db = base('resident2');
    await assertFails(setDoc(doc(db, `${S}/n1`), signalement('resident2', {
      photoUrl: 'https://exemple.com/image.jpg',
    })));
    await assertFails(setDoc(doc(db, `${S}/n1`), signalement('resident2', {
      photoUrl: 'https://res.cloudinary.com/autrecompte/image/upload/x.jpg',
    })));
    await assertFails(setDoc(doc(db, `${S}/n1`), signalement('resident2', {
      photoUrl: 'http://res.cloudinary.com/pu3lxdrf/image/upload/x.jpg',
    })));
  });

  test('position : un point GPS ; danger : un booléen', async () => {
    const db = base('resident2');
    await assertFails(setDoc(doc(db, `${S}/n1`), signalement('resident2', { position: '36.8,10.1' })));
    await assertFails(setDoc(doc(db, `${S}/n1`), signalement('resident2', { danger: 'oui' })));
  });
});

// ---------------------------------------------------------------------
describe('l\'auteur corrige son signalement', () => {
  test('tant qu\'il est en attente : texte, danger, position, photo', async () => {
    await assertSucceeds(updateDoc(doc(base('resident1'), `${S}/attente`), {
      titre: 'Grosse fuite d\'eau',
      danger: true,
      position: new GeoPoint(36.8625, 10.17),
      photoUrl: PHOTO,
    }));
  });

  test('il peut retirer la photo et la position (FieldValue.delete)', async () => {
    await assertSucceeds(updateDoc(doc(base('resident1'), `${S}/avecphoto`), {
      photoUrl: deleteField(),
      position: deleteField(),
    }));
  });

  test('plus après la prise en charge', async () => {
    await assertFails(updateDoc(doc(base('resident1'), `${S}/encours`), { titre: 'Changé' }));
  });

  test('jamais le statut, le compteur ou l\'auteur', async () => {
    const db = base('resident1');
    await assertFails(updateDoc(doc(db, `${S}/attente`), { statut: 'resolu' }));
    await assertFails(updateDoc(doc(db, `${S}/attente`), { nbConfirmations: 10 }));
    await assertFails(updateDoc(doc(db, `${S}/attente`), { auteurId: 'resident2' }));
  });

  test('pas une photo d\'un autre site, ni un titre trop court', async () => {
    const db = base('resident1');
    await assertFails(updateDoc(doc(db, `${S}/attente`), { photoUrl: 'https://exemple.com/x.jpg' }));
    await assertFails(updateDoc(doc(db, `${S}/attente`), { titre: 'ab' }));
  });

  test('un autre membre ne peut pas corriger', async () => {
    await assertFails(updateDoc(doc(base('resident2'), `${S}/attente`), { titre: 'Changé' }));
  });
});

// ---------------------------------------------------------------------
describe('l\'admin change le statut', () => {
  test('l\'admin passe un signalement en cours, puis résolu', async () => {
    const db = base('admin1');
    await assertSucceeds(updateDoc(doc(db, `${S}/attente`), { statut: 'enCours' }));
    await assertSucceeds(updateDoc(doc(db, `${S}/attente`), { statut: 'resolu' }));
  });

  test('un statut inconnu est refusé ; l\'admin ne change pas le contenu', async () => {
    const db = base('admin1');
    await assertFails(updateDoc(doc(db, `${S}/attente`), { statut: 'archive' }));
    await assertFails(updateDoc(doc(db, `${S}/attente`), { titre: 'Changé' }));
  });

  test('un résident ne change pas le statut', async () => {
    await assertFails(updateDoc(doc(base('resident2'), `${S}/attente`), { statut: 'resolu' }));
  });
});

// ---------------------------------------------------------------------
describe('« Sa7, ena zeda » (confirmer)', () => {
  test('un voisin confirme : fiche + compteur dans le même lot', async () => {
    await assertSucceeds(confirmer('resident2', 'attente'));
    await assertSucceeds(confirmer('admin1', 'encours'));
  });

  test('une seule fois par voisin', async () => {
    await assertSucceeds(confirmer('resident2', 'attente'));
    await assertFails(confirmer('resident2', 'attente'));
  });

  test('jamais son propre signalement', async () => {
    await assertFails(confirmer('resident1', 'attente'));
  });

  test('jamais un signalement clôturé (résolu ou refusé)', async () => {
    await assertFails(confirmer('resident2', 'resolu'));
    await assertFails(confirmer('resident2', 'refuse'));
  });

  test('la fiche sans le compteur, ou le compteur sans la fiche : refusés', async () => {
    const db = base('resident2');
    await assertFails(setDoc(doc(db, `${S}/attente/confirmations/resident2`), {
      date: Timestamp.now(),
    }));
    await assertFails(updateDoc(doc(db, `${S}/attente`), { nbConfirmations: increment(1) }));
  });

  test('une confirmation ne se modifie ni ne se supprime', async () => {
    await assertSucceeds(confirmer('resident2', 'attente'));
    const fiche = doc(base('resident2'), `${S}/attente/confirmations/resident2`);
    await assertFails(updateDoc(fiche, { date: Timestamp.now() }));
    await assertFails(deleteDoc(fiche));
  });
});

// ---------------------------------------------------------------------
describe('supprimer un signalement', () => {
  test('l\'auteur, tant qu\'il est en attente', async () => {
    await assertSucceeds(deleteDoc(doc(base('resident1'), `${S}/attente`)));
    await assertFails(deleteDoc(doc(base('resident1'), `${S}/encours`)));
  });

  test('l\'admin, quel que soit le statut ; un autre membre, jamais', async () => {
    await assertFails(deleteDoc(doc(base('resident2'), `${S}/attente`)));
    await assertSucceeds(deleteDoc(doc(base('admin1'), `${S}/encours`)));
  });
});

// ---------------------------------------------------------------------
// Historique des statuts : quartiers/q1/signalements/{id}/historique/{auto}
function etape(parId, statut, extra = {}) {
  return {
    statut,
    note: '',
    date: Timestamp.now(),
    parId,
    parNom: 'Test T.',
    ...extra,
  };
}

/// Création comme l'app : le signalement ET sa 1re étape dans le même lot.
function creerAvecHistorique(uid, id, extraEtape = {}, extraSignalement = {}) {
  const db = base(uid);
  const batch = writeBatch(db);
  batch.set(doc(db, `${S}/${id}`), signalement(uid, extraSignalement));
  batch.set(doc(db, `${S}/${id}/historique/e1`), etape(uid, 'enAttente', extraEtape));
  return batch.commit();
}

/// Changement de statut comme l'app : le statut ET l'étape dans le même lot.
function changerStatutAvecHistorique(uid, id, statut, note = '', statutEtape = statut) {
  const db = base(uid);
  const batch = writeBatch(db);
  batch.update(doc(db, `${S}/${id}`), { statut });
  batch.set(doc(db, `${S}/${id}/historique/e2`), etape(uid, statutEtape, { note }));
  return batch.commit();
}

describe('historique : 1re étape à la création', () => {
  test('l\'auteur crée le signalement et sa 1re étape ensemble', async () => {
    await assertSucceeds(creerAvecHistorique('resident2', 'n1'));
  });

  test('une étape seule sur un signalement existant : refusée', async () => {
    await assertFails(setDoc(doc(base('resident1'), `${S}/attente/historique/x`),
      etape('resident1', 'enAttente')));
  });

  test('la 1re étape est "en attente", au nom de l\'auteur', async () => {
    await assertFails(creerAvecHistorique('resident2', 'n1', { statut: 'enCours' }));
    await assertFails(creerAvecHistorique('resident2', 'n1', { parId: 'admin1' }));
  });

  test('note de 200 caractères au plus, aucun champ inconnu', async () => {
    await assertSucceeds(creerAvecHistorique('resident2', 'n1', { note: 'a'.repeat(200) }));
    await assertFails(creerAvecHistorique('resident2', 'n2', { note: 'a'.repeat(201) }));
    await assertFails(creerAvecHistorique('resident2', 'n3', { important: true }));
  });
});

describe('historique : changement de statut par l\'admin', () => {
  test('le statut et l\'étape ensemble, avec une note', async () => {
    await assertSucceeds(changerStatutAvecHistorique('admin1', 'attente', 'enCours',
      'Intervention prévue jeudi'));
  });

  test('l\'étape doit recopier le NOUVEAU statut', async () => {
    await assertFails(changerStatutAvecHistorique('admin1', 'attente', 'enCours', '', 'resolu'));
  });

  test('pas d\'étape sans vrai changement de statut', async () => {
    await assertFails(setDoc(doc(base('admin1'), `${S}/encours/historique/x`),
      etape('admin1', 'enCours')));
  });

  test('refuser demande une explication (3 caractères au moins)', async () => {
    await assertFails(changerStatutAvecHistorique('admin1', 'attente', 'refuse', ''));
    await assertFails(changerStatutAvecHistorique('admin1', 'attente', 'refuse', 'ok'));
    await assertSucceeds(changerStatutAvecHistorique('admin1', 'attente', 'refuse',
      'Déjà signalé à la municipalité'));
  });

  test('un résident ne peut pas écrire d\'étape', async () => {
    await assertFails(changerStatutAvecHistorique('resident2', 'attente', 'enCours'));
  });
});

describe('historique : lecture, jamais modifié', () => {
  test('un membre lit l\'historique ; un membre en attente, non', async () => {
    await assertSucceeds(creerAvecHistorique('resident2', 'n1'));
    await assertSucceeds(getDoc(doc(base('resident1'), `${S}/n1/historique/e1`)));
    await assertFails(getDoc(doc(base('attente1'), `${S}/n1/historique/e1`)));
  });

  test('une étape ne se modifie ni ne se supprime', async () => {
    await assertSucceeds(creerAvecHistorique('resident2', 'n1'));
    const fiche = doc(base('resident2'), `${S}/n1/historique/e1`);
    await assertFails(updateDoc(fiche, { note: 'changé' }));
    await assertFails(deleteDoc(fiche));
    await assertFails(deleteDoc(doc(base('admin1'), `${S}/n1/historique/e1`)));
  });
});
