// Tests des règles Firestore du Module 4 (événements, sondages, présence).
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
  doc,
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

const DANS_UNE_SEMAINE = Timestamp.fromDate(new Date(Date.now() + 7 * 24 * 3600 * 1000));
const DANS_UNE_HEURE = Timestamp.fromDate(new Date(Date.now() + 3600 * 1000));

// Un événement comme celui que l'app crée (Evenement.toMap)
function evenement(organisateurId, extra = {}) {
  return {
    titre: 'Fête des voisins',
    description: '',
    date: DANS_UNE_SEMAINE,
    dateFin: null,
    lieu: 'Jardin',
    categorie: 'fete',
    organisateurId,
    organisateur: 'Leila T.',
    nbParticipants: 0,
    nbInteresses: 0,
    annule: false,
    officiel: false,
    placesMax: 0,
    position: null,
    photoUrl: null,
    ...extra,
  };
}

const E = 'quartiers/q1/evenements';

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
    await setDoc(doc(db, 'utilisateurs/admin1'), membre('Amira', 'q1', 'actif', 'admin'));
    await setDoc(doc(db, 'utilisateurs/leader1'), membre('Leila', 'q1', 'actif', 'leader'));
    await setDoc(doc(db, 'utilisateurs/resident1'), membre('Youssef', 'q1', 'actif'));
    await setDoc(doc(db, 'utilisateurs/resident2'), membre('Sarra', 'q1', 'actif'));
    await setDoc(doc(db, 'utilisateurs/attente1'), membre('Hedi', 'q1', 'enAttente'));
    // Un événement de la leader, un autre complet (1 place prise)
    await setDoc(doc(db, `${E}/fete`), evenement('leader1'));
    await setDoc(doc(db, `${E}/complet`), evenement('leader1', { placesMax: 1, nbParticipants: 1 }));
    await setDoc(doc(db, `${E}/complet/participants/resident2`), { nom: 'Sarra T.' });
    // Un événement qui commence dans 1 h (pointage ouvert) + son code secret
    await setDoc(doc(db, `${E}/bientot`), evenement('leader1', { date: DANS_UNE_HEURE, nbParticipants: 1 }));
    await setDoc(doc(db, `${E}/bientot/participants/resident1`), { nom: 'Youssef T.' });
    await setDoc(doc(db, `${E}/bientot/prive/presence`), { code: 'SECRET1234' });
    // Un sondage à 2 choix
    await setDoc(doc(db, 'quartiers/q1/sondages/s1'), {
      question: 'Quelle date ?',
      options: ['Samedi', 'Dimanche'],
      dateFin: DANS_UNE_SEMAINE,
      proposeParId: 'leader1',
      proposePar: 'Leila T.',
    });
  });
});

// ---------------------------------------------------------------------
describe('créer un événement', () => {
  test('une leader crée un événement', async () => {
    await assertSucceeds(setDoc(doc(base('leader1'), `${E}/nouveau`), evenement('leader1')));
  });

  test('un résident ne peut pas créer d\'événement', async () => {
    await assertFails(setDoc(doc(base('resident1'), `${E}/nouveau`), evenement('resident1')));
  });

  test('un membre en attente non plus', async () => {
    await assertFails(setDoc(doc(base('attente1'), `${E}/nouveau`), evenement('attente1')));
  });

  test('seul l\'admin crée un événement officiel', async () => {
    await assertFails(
      setDoc(doc(base('leader1'), `${E}/off`), evenement('leader1', { officiel: true })),
    );
    await assertSucceeds(
      setDoc(doc(base('admin1'), `${E}/off`), evenement('admin1', { officiel: true })),
    );
  });

  test('impossible de commencer avec des participants', async () => {
    await assertFails(
      setDoc(doc(base('leader1'), `${E}/triche`), evenement('leader1', { nbParticipants: 5 })),
    );
  });

  test('la photo doit venir de NOTRE compte Cloudinary', async () => {
    await assertSucceeds(
      setDoc(doc(base('leader1'), `${E}/photo`), evenement('leader1', {
        photoUrl: 'https://res.cloudinary.com/pu3lxdrf/image/upload/v1/houmani/evenements/a.jpg',
      })),
    );
    await assertFails(
      setDoc(doc(base('leader1'), `${E}/photo2`), evenement('leader1', {
        photoUrl: 'https://exemple.com/pirate.jpg',
      })),
    );
  });
});

describe('modifier un événement', () => {
  test('l\'organisatrice et l\'admin modifient, un résident non', async () => {
    await assertSucceeds(updateDoc(doc(base('leader1'), `${E}/fete`), { titre: 'Grande fête' }));
    await assertSucceeds(updateDoc(doc(base('admin1'), `${E}/fete`), { lieu: 'Salle' }));
    await assertFails(updateDoc(doc(base('resident1'), `${E}/fete`), { titre: 'Piraté' }));
  });

  test('l\'organisatrice ne peut pas changer le compteur à la main', async () => {
    await assertFails(updateDoc(doc(base('leader1'), `${E}/fete`), { nbParticipants: 50 }));
  });

  test('lier un service commun (D4)', async () => {
    await assertSucceeds(
      updateDoc(doc(base('leader1'), `${E}/fete`), { serviceId: 's1', serviceNom: 'Ménage' }),
    );
  });
});

describe('participer', () => {
  test('ma fiche + le compteur +1 dans le même batch', async () => {
    const db = base('resident1');
    const batch = writeBatch(db);
    batch.set(doc(db, `${E}/fete/participants/resident1`), { nom: 'Youssef T.' });
    batch.update(doc(db, `${E}/fete`), { nbParticipants: increment(1) });
    await assertSucceeds(batch.commit());
  });

  test('le compteur +1 sans ma fiche est refusé', async () => {
    await assertFails(
      updateDoc(doc(base('resident1'), `${E}/fete`), { nbParticipants: increment(1) }),
    );
  });

  test('pas d\'inscription au nom d\'un autre', async () => {
    const db = base('resident1');
    const batch = writeBatch(db);
    batch.set(doc(db, `${E}/fete/participants/resident2`), { nom: 'Sarra T.' });
    batch.update(doc(db, `${E}/fete`), { nbParticipants: increment(1) });
    await assertFails(batch.commit());
  });

  test('complet : pas de place en plus', async () => {
    const db = base('resident1');
    const batch = writeBatch(db);
    batch.set(doc(db, `${E}/complet/participants/resident1`), { nom: 'Youssef T.' });
    batch.update(doc(db, `${E}/complet`), { nbParticipants: increment(1) });
    await assertFails(batch.commit());
  });

  test('liste d\'attente : seulement quand c\'est complet', async () => {
    await assertSucceeds(
      setDoc(doc(base('resident1'), `${E}/complet/attente/resident1`), { nom: 'Youssef T.' }),
    );
    await assertFails(
      setDoc(doc(base('resident1'), `${E}/fete/attente/resident1`), { nom: 'Youssef T.' }),
    );
  });
});

describe('sondages et votes secrets', () => {
  test('un résident ne peut pas créer de sondage', async () => {
    await assertFails(
      setDoc(doc(base('resident1'), 'quartiers/q1/sondages/s2'), {
        question: 'Q ?', options: ['A', 'B'], dateFin: DANS_UNE_SEMAINE,
        proposeParId: 'resident1', proposePar: 'Youssef T.',
      }),
    );
  });

  test('voter : mon vote + le compteur de ce choix, dans le même batch', async () => {
    const db = base('resident1');
    const batch = writeBatch(db);
    batch.set(doc(db, 'quartiers/q1/sondages/s1/votes/resident1'), { choix: 1 });
    batch.set(doc(db, 'quartiers/q1/sondages/s1/compteurs/1'), { n: 1 });
    await assertSucceeds(batch.commit());
  });

  test('voter sans compter (ou compter un autre choix) est refusé', async () => {
    const db = base('resident1');
    await assertFails(setDoc(doc(db, 'quartiers/q1/sondages/s1/votes/resident1'), { choix: 0 }));
    const batch = writeBatch(db);
    batch.set(doc(db, 'quartiers/q1/sondages/s1/votes/resident1'), { choix: 0 });
    batch.set(doc(db, 'quartiers/q1/sondages/s1/compteurs/1'), { n: 1 });
    await assertFails(batch.commit());
  });

  test('un vote est secret : personne d\'autre ne le lit', async () => {
    await env.withSecurityRulesDisabled(async (contexte) => {
      await setDoc(doc(contexte.firestore(), 'quartiers/q1/sondages/s1/votes/resident2'), { choix: 0 });
    });
    await assertSucceeds(getDoc(doc(base('resident2'), 'quartiers/q1/sondages/s1/votes/resident2')));
    await assertFails(getDoc(doc(base('resident1'), 'quartiers/q1/sondages/s1/votes/resident2')));
    await assertFails(getDoc(doc(base('leader1'), 'quartiers/q1/sondages/s1/votes/resident2')));
  });

  test('un vote est définitif', async () => {
    await env.withSecurityRulesDisabled(async (contexte) => {
      await setDoc(doc(contexte.firestore(), 'quartiers/q1/sondages/s1/votes/resident1'), { choix: 0 });
    });
    await assertFails(
      updateDoc(doc(base('resident1'), 'quartiers/q1/sondages/s1/votes/resident1'), { choix: 1 }),
    );
  });
});

describe('présence par QR code (A21)', () => {
  test('seuls l\'organisatrice et l\'admin lisent le code secret', async () => {
    await assertSucceeds(getDoc(doc(base('leader1'), `${E}/bientot/prive/presence`)));
    await assertSucceeds(getDoc(doc(base('admin1'), `${E}/bientot/prive/presence`)));
    await assertFails(getDoc(doc(base('resident1'), `${E}/bientot/prive/presence`)));
  });

  test('un inscrit se pointe avec le BON code', async () => {
    const db = base('resident1');
    await assertFails(
      setDoc(doc(db, `${E}/bientot/presences/resident1`), { code: 'FAUX', nom: 'Youssef T.' }),
    );
    await assertSucceeds(
      setDoc(doc(db, `${E}/bientot/presences/resident1`), { code: 'SECRET1234', nom: 'Youssef T.' }),
    );
  });

  test('pas inscrit : refusé même avec le bon code', async () => {
    await assertFails(
      setDoc(doc(base('resident2'), `${E}/bientot/presences/resident2`), {
        code: 'SECRET1234', nom: 'Sarra T.',
      }),
    );
  });

  test('trop tôt (une semaine avant) : refusé', async () => {
    await env.withSecurityRulesDisabled(async (contexte) => {
      const db = contexte.firestore();
      await setDoc(doc(db, `${E}/fete/participants/resident1`), { nom: 'Youssef T.' });
      await setDoc(doc(db, `${E}/fete/prive/presence`), { code: 'CODEFETE' });
    });
    await assertFails(
      setDoc(doc(base('resident1'), `${E}/fete/presences/resident1`), {
        code: 'CODEFETE', nom: 'Youssef T.',
      }),
    );
  });
});

describe('assistant IA (suggestionsIA)', () => {
  test('les leaders et l\'admin lisent les idées, pas un résident', async () => {
    await env.withSecurityRulesDisabled(async (contexte) => {
      await setDoc(doc(contexte.firestore(), 'quartiers/q1/suggestionsIA/courant'), { suggestions: [] });
    });
    await assertSucceeds(getDoc(doc(base('leader1'), 'quartiers/q1/suggestionsIA/courant')));
    await assertSucceeds(getDoc(doc(base('admin1'), 'quartiers/q1/suggestionsIA/courant')));
    await assertFails(getDoc(doc(base('resident1'), 'quartiers/q1/suggestionsIA/courant')));
  });

  test('personne n\'écrit les idées depuis l\'application', async () => {
    await assertFails(
      setDoc(doc(base('admin1'), 'quartiers/q1/suggestionsIA/courant'), { suggestions: [] }),
    );
  });
});
