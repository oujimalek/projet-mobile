// Tests de src/limites.js (sans Cloudflare) : node --test
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { cleLimite, compterAppel, jourTunisie, LIMITES_PAR_JOUR } from '../src/limites.js';

// Un faux KV en mémoire (get / put comme Cloudflare KV)
function fauxKV() {
  const donnees = new Map();
  return {
    donnees,
    async get(cle) {
      return donnees.has(cle) ? donnees.get(cle) : null;
    },
    async put(cle, valeur) {
      donnees.set(cle, valeur);
    },
  };
}

const MIDI = new Date('2026-11-12T12:00:00Z');

test('les limites demandées', () => {
  assert.deepEqual(LIMITES_PAR_JOUR, {
    '/ameliorer': 20,
    '/correspondances': 20,
    '/notifier': 10,
    '/suggestions': 5,
  });
});

test('le jour est celui de la Tunisie (UTC+1)', () => {
  assert.equal(jourTunisie(new Date('2026-11-12T22:59:00Z')), '2026-11-12');
  assert.equal(jourTunisie(new Date('2026-11-12T23:00:00Z')), '2026-11-13');
  assert.equal(cleLimite('/notifier', 'u1', MIDI), '/notifier:u1:2026-11-12');
});

test('/suggestions : 5 appels acceptés, le 6e refusé avec un message', async () => {
  const kv = fauxKV();
  for (let i = 0; i < 5; i++) {
    assert.deepEqual(await compterAppel(kv, '/suggestions', 'u1', MIDI), { ok: true });
  }
  const refus = await compterAppel(kv, '/suggestions', 'u1', MIDI);
  assert.equal(refus.ok, false);
  assert.match(refus.message, /limite/);
  assert.match(refus.message, /demain/);
  // Un refus n'écrit rien : le compteur reste à 5
  assert.equal(kv.donnees.get('/suggestions:u1:2026-11-12'), '5');
});

test('compté par utilisateur, par route et par jour', async () => {
  const kv = fauxKV();
  for (let i = 0; i < 10; i++) {
    await compterAppel(kv, '/notifier', 'u1', MIDI);
  }
  assert.equal((await compterAppel(kv, '/notifier', 'u1', MIDI)).ok, false);
  assert.equal((await compterAppel(kv, '/notifier', 'u2', MIDI)).ok, true);
  assert.equal((await compterAppel(kv, '/ameliorer', 'u1', MIDI)).ok, true);
  const demain = new Date('2026-11-13T12:00:00Z');
  assert.equal((await compterAppel(kv, '/notifier', 'u1', demain)).ok, true);
});

test('sans KV, ou KV en panne : l\'appel passe', async () => {
  assert.deepEqual(await compterAppel(undefined, '/ameliorer', 'u1', MIDI), { ok: true });
  const enPanne = {
    async get() {
      throw new Error('KV indisponible');
    },
  };
  assert.deepEqual(await compterAppel(enPanne, '/ameliorer', 'u1', MIDI), { ok: true });
});
