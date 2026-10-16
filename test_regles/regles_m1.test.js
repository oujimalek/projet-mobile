// Tests des règles Firestore du Module 1 (utilisateurs, quartiers, codes).
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
  collection,
  deleteDoc,
  doc,
  getDoc,
  GeoPoint,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from 'firebase/firestore';

let env;

// Un profil comme celui que l'app crée à l'inscription (Utilisateur.toMap)
function nouveauProfil(email) {
  return {
    prenom: 'Nour',
    nom: 'Hamdi',
    email,
    telephone: '+216 20 000 000',
    quartierId: null,
    quartierNom: '',
    residence: '',
    logement: '',
    statut: 'enAttente',
    role: 'resident',
    competences: [],
    avatar: '',
    dateDemande: null,
  };
}

function membre(prenom, quartierId, statut, role = 'resident') {
  return {
    prenom,
    nom: 'Test',
    email: `${prenom.toLowerCase()}@houmani.tn`,
    telephone: '',
    quartierId,
    quartierNom: quartierId === 'q1' ? 'El Yasmine' : 'El Wafa',
    residence: quartierId === 'q1' ? 'El Yasmine' : 'El Wafa',
    logement: '',
    statut,
    role,
    competences: [],
    avatar: '',
    dateDemande: Timestamp.fromDate(new Date('2026-10-01')),
  };
}

// La base vue par un utilisateur connecté (uid + jeton)
function base(uid, emailVerifie = true) {
  return env
    .authenticatedContext(uid, {
      email: `${uid}@houmani.tn`,
      email_verified: emailVerifie,
    })
    .firestore();
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-houmani',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});

after(async () => {
  await env.cleanup();
});

// Avant chaque test : base vide, puis les données de départ (écrites
// sans les règles, comme dans la console Firebase)
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (contexte) => {
    const db = contexte.firestore();
    await setDoc(doc(db, 'quartiers/q1'), { nom: 'El Yasmine', localisation: 'Ennasr 2' });
    await setDoc(doc(db, 'quartiers/q2'), { nom: 'El Wafa', localisation: 'Ennasr 1' });
    await setDoc(doc(db, 'codesQuartier/YAS72B'), { quartierId: 'q1', quartierNom: 'El Yasmine' });
    await setDoc(doc(db, 'utilisateurs/admin1'), membre('Amira', 'q1', 'actif', 'admin'));
    await setDoc(doc(db, 'utilisateurs/actif1'), membre('Youssef', 'q1', 'actif'));
    await setDoc(doc(db, 'utilisateurs/attente1'), membre('Sarra', 'q1', 'enAttente'));
    await setDoc(doc(db, 'utilisateurs/bloque1'), membre('Walid', 'q1', 'bloque'));
    await setDoc(doc(db, 'utilisateurs/refuse1'), membre('Hedi', 'q1', 'refuse'));
    await setDoc(doc(db, 'utilisateurs/admin2'), membre('Karim', 'q2', 'actif', 'admin'));
  });
});

// ---------------------------------------------------------------------
describe('inscription (create)', () => {
  test('on crée SON profil, en attente, sans quartier', async () => {
    const db = base('nouveau', false);
    await assertSucceeds(
      setDoc(doc(db, 'utilisateurs/nouveau'), nouveauProfil('nouveau@houmani.tn')),
    );
  });

  test('pas de profil pour quelqu\'un d\'autre', async () => {
    const db = base('nouveau', false);
    await assertFails(
      setDoc(doc(db, 'utilisateurs/autre'), nouveauProfil('nouveau@houmani.tn')),
    );
  });

  test('impossible de se déclarer admin ou actif', async () => {
    const db = base('nouveau', false);
    await assertFails(
      setDoc(doc(db, 'utilisateurs/nouveau'), {
        ...nouveauProfil('nouveau@houmani.tn'),
        role: 'admin',
      }),
    );
    await assertFails(
      setDoc(doc(db, 'utilisateurs/nouveau'), {
        ...nouveauProfil('nouveau@houmani.tn'),
        statut: 'actif',
      }),
    );
  });

  test('impossible de choisir un quartier avant de vérifier son e-mail', async () => {
    const db = base('nouveau', false);
    await assertFails(
      setDoc(doc(db, 'utilisateurs/nouveau'), {
        ...nouveauProfil('nouveau@houmani.tn'),
        quartierId: 'q1',
      }),
    );
  });

  test('e-mail différent de celui du compte : refusé', async () => {
    const db = base('nouveau', false);
    await assertFails(
      setDoc(doc(db, 'utilisateurs/nouveau'), nouveauProfil('autre@houmani.tn')),
    );
  });

  test('champ inconnu : refusé', async () => {
    const db = base('nouveau', false);
    await assertFails(
      setDoc(doc(db, 'utilisateurs/nouveau'), {
        ...nouveauProfil('nouveau@houmani.tn'),
        estSuperAdmin: true,
      }),
    );
  });
});

// ---------------------------------------------------------------------
describe('modifier son profil (compte actif)', () => {
  test('nom, téléphone, logement, compétences, avatar : autorisé', async () => {
    const db = base('actif1');
    await assertSucceeds(
      updateDoc(doc(db, 'utilisateurs/actif1'), {
        prenom: 'Youssef',
        nom: 'Ben Ali',
        telephone: '+216 22 000 000',
        logement: 'Bloc A',
        competences: ['Plomberie'],
        avatar: 'chat',
      }),
    );
  });

  test('statut, rôle, e-mail ou résidence : refusé', async () => {
    const db = base('actif1');
    const profil = doc(db, 'utilisateurs/actif1');
    await assertFails(updateDoc(profil, { role: 'admin' }));
    await assertFails(updateDoc(profil, { statut: 'bloque' }));
    await assertFails(updateDoc(profil, { email: 'admin@houmani.tn' }));
    await assertFails(updateDoc(profil, { residence: 'Bloc Z' }));
  });

  test('un compte bloqué ne modifie pas son profil', async () => {
    const db = base('bloque1');
    await assertFails(updateDoc(doc(db, 'utilisateurs/bloque1'), { prenom: 'X' }));
  });
});

// ---------------------------------------------------------------------
describe('rejoindre un quartier', () => {
  // Comme FirebaseUtilisateurRepository.rejoindreQuartier
  function demande(quartierId) {
    return {
      quartierId,
      quartierNom: 'El Wafa',
      residence: 'El Wafa',
      statut: 'enAttente',
      dateDemande: serverTimestamp(),
    };
  }

  test('compte refusé, e-mail vérifié : il redemande un quartier', async () => {
    const db = base('refuse1');
    await assertSucceeds(updateDoc(doc(db, 'utilisateurs/refuse1'), demande('q2')));
  });

  test('e-mail pas vérifié : refusé', async () => {
    const db = base('attente1', false);
    await assertFails(updateDoc(doc(db, 'utilisateurs/attente1'), demande('q2')));
  });

  test('quartier qui n\'existe pas : refusé', async () => {
    const db = base('attente1');
    await assertFails(updateDoc(doc(db, 'utilisateurs/attente1'), demande('q999')));
  });

  test('date de demande choisie par le téléphone : refusé', async () => {
    const db = base('attente1');
    await assertFails(
      updateDoc(doc(db, 'utilisateurs/attente1'), {
        ...demande('q2'),
        dateDemande: Timestamp.fromDate(new Date('2020-01-01')),
      }),
    );
  });

  test('en profiter pour changer son e-mail : refusé', async () => {
    const db = base('attente1');
    await assertFails(
      updateDoc(doc(db, 'utilisateurs/attente1'), {
        ...demande('q2'),
        email: 'faux@houmani.tn',
      }),
    );
  });

  test('un compte bloqué ne peut pas changer de quartier', async () => {
    const db = base('bloque1');
    await assertFails(updateDoc(doc(db, 'utilisateurs/bloque1'), demande('q2')));
  });

  // Écran Mon quartier : un résident actif quitte son quartier
  test('résident actif : il quitte son quartier pour un autre', async () => {
    const db = base('actif1');
    await assertSucceeds(updateDoc(doc(db, 'utilisateurs/actif1'), demande('q2')));
  });

  test('résident actif : redemander SON quartier (redevenir en attente) : refusé', async () => {
    const db = base('actif1');
    await assertFails(updateDoc(doc(db, 'utilisateurs/actif1'), demande('q1')));
  });

  test('admin actif : il ne peut pas quitter son quartier', async () => {
    const db = base('admin1');
    await assertFails(updateDoc(doc(db, 'utilisateurs/admin1'), demande('q2')));
  });

  test('résident actif : pas de rôle admin en changeant de quartier', async () => {
    const db = base('actif1');
    await assertFails(
      updateDoc(doc(db, 'utilisateurs/actif1'), { ...demande('q2'), role: 'admin' }),
    );
  });

  test('résident actif : il doit repasser en attente', async () => {
    const db = base('actif1');
    await assertFails(
      updateDoc(doc(db, 'utilisateurs/actif1'), { ...demande('q2'), statut: 'actif' }),
    );
  });
});

// ---------------------------------------------------------------------
describe('administration des membres', () => {
  test('l\'admin valide une demande de SON quartier', async () => {
    const db = base('admin1');
    await assertSucceeds(updateDoc(doc(db, 'utilisateurs/attente1'), { statut: 'actif' }));
  });

  test('l\'admin bloque puis débloque un membre', async () => {
    const db = base('admin1');
    await assertSucceeds(updateDoc(doc(db, 'utilisateurs/actif1'), { statut: 'bloque' }));
    await assertSucceeds(updateDoc(doc(db, 'utilisateurs/actif1'), { statut: 'actif' }));
  });

  test('l\'admin ne change que le statut', async () => {
    const db = base('admin1');
    await assertFails(
      updateDoc(doc(db, 'utilisateurs/attente1'), { statut: 'actif', role: 'admin' }),
    );
  });

  test('l\'admin d\'un autre quartier : refusé', async () => {
    const db = base('admin2');
    await assertFails(updateDoc(doc(db, 'utilisateurs/attente1'), { statut: 'actif' }));
  });

  test('l\'admin ne change pas son propre statut', async () => {
    const db = base('admin1');
    await assertFails(updateDoc(doc(db, 'utilisateurs/admin1'), { statut: 'bloque' }));
  });

  test('un résident ne valide personne', async () => {
    const db = base('actif1');
    await assertFails(updateDoc(doc(db, 'utilisateurs/attente1'), { statut: 'actif' }));
  });
});

// ---------------------------------------------------------------------
describe('lire les profils', () => {
  test('chacun lit son propre profil, même bloqué', async () => {
    await assertSucceeds(getDoc(doc(base('bloque1'), 'utilisateurs/bloque1')));
    await assertSucceeds(getDoc(doc(base('attente1'), 'utilisateurs/attente1')));
  });

  test('un résident actif lit un voisin actif, pas une demande en attente', async () => {
    const db = base('actif1');
    await assertSucceeds(getDoc(doc(db, 'utilisateurs/admin1')));
    await assertFails(getDoc(doc(db, 'utilisateurs/attente1')));
    await assertFails(getDoc(doc(db, 'utilisateurs/bloque1')));
  });

  test('l\'admin lit les demandes en attente de son quartier', async () => {
    const db = base('admin1');
    await assertSucceeds(getDoc(doc(db, 'utilisateurs/attente1')));
  });

  test('personne ne lit le profil d\'un autre quartier', async () => {
    const db = base('admin2');
    await assertFails(getDoc(doc(db, 'utilisateurs/actif1')));
  });

  test('un compte en attente ne lit pas les voisins', async () => {
    const db = base('attente1');
    await assertFails(getDoc(doc(db, 'utilisateurs/actif1')));
  });

  test('requête des voisins (getVoisins) : quartier + statut actif', async () => {
    const db = base('actif1');
    await assertSucceeds(
      getDocs(
        query(
          collection(db, 'utilisateurs'),
          where('quartierId', '==', 'q1'),
          where('statut', '==', 'actif'),
        ),
      ),
    );
  });

  test('requête des demandes en attente : admin oui, résident non', async () => {
    const requete = (db) =>
      getDocs(
        query(
          collection(db, 'utilisateurs'),
          where('quartierId', '==', 'q1'),
          where('statut', '==', 'enAttente'),
        ),
      );
    await assertSucceeds(requete(base('admin1')));
    await assertFails(requete(base('actif1')));
  });

  test('requête sans filtre de quartier : refusée', async () => {
    const db = base('admin1');
    await assertFails(getDocs(collection(db, 'utilisateurs')));
  });
});

// ---------------------------------------------------------------------
describe('sécurité du compte (écran Paramètres)', () => {
  // base(uid) donne le jeton "<uid>@houmani.tn" : c'est l'e-mail de
  // Firebase Auth après le clic sur le lien de changement
  test('on recopie dans son profil l\'e-mail de Firebase Auth', async () => {
    const db = base('actif1');
    await assertSucceeds(
      updateDoc(doc(db, 'utilisateurs/actif1'), { email: 'actif1@houmani.tn' }),
    );
  });

  test('pas un autre e-mail que celui du jeton', async () => {
    const db = base('actif1');
    await assertFails(
      updateDoc(doc(db, 'utilisateurs/actif1'), { email: 'pirate@houmani.tn' }),
    );
  });

  test('pas d\'autre champ avec l\'e-mail (ex : le rôle)', async () => {
    const db = base('attente1');
    await assertFails(
      updateDoc(doc(db, 'utilisateurs/attente1'), {
        email: 'attente1@houmani.tn',
        role: 'admin',
      }),
    );
  });

  test('pas l\'e-mail d\'un autre utilisateur', async () => {
    const db = base('actif1');
    await assertFails(
      updateDoc(doc(db, 'utilisateurs/admin1'), { email: 'actif1@houmani.tn' }),
    );
  });

  test('on supprime SON compte (même en attente)', async () => {
    await assertSucceeds(deleteDoc(doc(base('actif1'), 'utilisateurs/actif1')));
    await assertSucceeds(deleteDoc(doc(base('attente1'), 'utilisateurs/attente1')));
  });

  test('pas le compte d\'un autre, même pour l\'admin', async () => {
    await assertFails(deleteDoc(doc(base('actif1'), 'utilisateurs/attente1')));
    await assertFails(deleteDoc(doc(base('admin1'), 'utilisateurs/actif1')));
  });

  test('l\'admin ne supprime pas son propre compte', async () => {
    await assertFails(deleteDoc(doc(base('admin1'), 'utilisateurs/admin1')));
  });
});

// ---------------------------------------------------------------------
describe('quartiers et codes d\'invitation', () => {
  test('un compte connecté lit les quartiers, sans pouvoir en créer', async () => {
    const db = base('attente1');
    await assertSucceeds(getDocs(collection(db, 'quartiers')));
    await assertFails(setDoc(doc(db, 'quartiers/q3'), { nom: 'Faux', localisation: '' }));
  });

  test('on lit LE code tapé, mais on ne liste pas les codes', async () => {
    const db = base('attente1');
    await assertSucceeds(getDoc(doc(db, 'codesQuartier/YAS72B')));
    await assertFails(getDocs(collection(db, 'codesQuartier')));
  });

  // Écran Mon quartier : l'admin affiche le code de son quartier
  function codesDe(db, quartierId) {
    return getDocs(
      query(collection(db, 'codesQuartier'), where('quartierId', '==', quartierId)),
    );
  }

  test('l\'admin liste les codes de SON quartier', async () => {
    await assertSucceeds(codesDe(base('admin1'), 'q1'));
  });

  test('l\'admin ne liste pas les codes d\'un autre quartier, ni tous les codes', async () => {
    await assertFails(codesDe(base('admin2'), 'q1'));
    await assertFails(getDocs(collection(base('admin1'), 'codesQuartier')));
  });

  test('un résident ne liste pas les codes, même de son quartier', async () => {
    await assertFails(codesDe(base('actif1'), 'q1'));
  });

  test('l\'admin ne crée pas de code', async () => {
    await assertFails(
      setDoc(doc(base('admin1'), 'codesQuartier/NOUV01'), {
        quartierId: 'q1',
        quartierNom: 'El Yasmine',
      }),
    );
  });

  test('sans être connecté : rien', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDocs(collection(db, 'quartiers')));
    await assertFails(getDoc(doc(db, 'codesQuartier/YAS72B')));
  });
});

describe('limites du quartier (contour)', () => {
  // Un triangle autour de la Charguia
  const limites = {
    contour: [
      new GeoPoint(36.84, 10.2),
      new GeoPoint(36.85, 10.21),
      new GeoPoint(36.84, 10.22),
    ],
    position: new GeoPoint(36.843, 10.21),
  };

  test('l\'admin trace les limites de SON quartier', async () => {
    await assertSucceeds(updateDoc(doc(base('admin1'), 'quartiers/q1'), limites));
  });

  test('l\'admin ne trace pas les limites d\'un autre quartier', async () => {
    await assertFails(updateDoc(doc(base('admin2'), 'quartiers/q1'), limites));
  });

  test('un résident ne trace pas les limites', async () => {
    await assertFails(updateDoc(doc(base('actif1'), 'quartiers/q1'), limites));
  });

  test('l\'admin ne change pas le nom du quartier', async () => {
    await assertFails(
      updateDoc(doc(base('admin1'), 'quartiers/q1'), { ...limites, nom: 'Autre' }),
    );
  });

  test('il faut au moins 3 coins', async () => {
    await assertFails(
      updateDoc(doc(base('admin1'), 'quartiers/q1'), {
        contour: limites.contour.slice(0, 2),
        position: limites.position,
      }),
    );
  });

  test('l\'admin ne supprime pas son quartier', async () => {
    await assertFails(deleteDoc(doc(base('admin1'), 'quartiers/q1')));
  });
});
