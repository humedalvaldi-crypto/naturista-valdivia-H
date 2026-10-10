import { beforeAll, describe, expect, it } from 'vitest';
import { makeApp, makeSigner } from './helpers';

let signer: Awaited<ReturnType<typeof makeSigner>>;
let call: ReturnType<typeof makeApp>;
beforeAll(async () => {
  signer = await makeSigner();
  call = makeApp(signer.jwks);
});

/** Cliente de prueba para una persona. */
async function person(uid: string, name = uid) {
  const token = await signer.sign({ sub: uid, name });
  const req = (method: string, path: string, body?: unknown) =>
    call(`/api/v1${path}`, {
      method,
      headers: { Authorization: `Bearer ${token}`, ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  const json = async <T = any>(method: string, path: string, body?: unknown) => {
    const res = await req(method, path, body);
    return { status: res.status, body: (res.status === 204 ? null : await res.json()) as T };
  };
  // Registra a la persona en la base de datos.
  await req('GET', '/me');
  return { uid, req, json };
}

const anon = async (path: string) => {
  const res = await call(`/api/v1${path}`);
  return { status: res.status, body: (await res.json()) as any };
};

describe('publicaciones', () => {
  it('crear exige sesión y valida el contenido', async () => {
    const res = await call('/api/v1/posts', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{"body":"hola"}' });
    expect(res.status).toBe(401);

    const ana = await person('soc-ana');
    expect((await ana.json('POST', '/posts', { body: '' })).status).toBe(400);
    expect((await ana.json('POST', '/posts', { body: 'x'.repeat(2001) })).status).toBe(400);
    expect((await ana.json('POST', '/posts', { body: 'hola', isAdmin: true })).status).toBe(400);
  });

  it('una publicación pública aparece en el feed general, también sin sesión', async () => {
    const ana = await person('soc-ana2', 'Ana');
    const created = await ana.json('POST', '/posts', { body: 'Vi un chucao en el humedal Angachilla', locationName: 'Angachilla' });
    expect(created.status).toBe(201);
    expect(created.body.data).toMatchObject({ body: 'Vi un chucao en el humedal Angachilla', likeCount: 0, commentCount: 0 });

    const feed = await anon('/posts');
    expect(feed.body.data.map((p: any) => p.id)).toContain(created.body.data.id);
  });

  it('solo el autor puede borrar', async () => {
    const ana = await person('soc-del-ana');
    const beto = await person('soc-del-beto');
    const { body } = await ana.json('POST', '/posts', { body: 'borrable' });
    expect((await beto.req('DELETE', `/posts/${body.data.id}`)).status).toBe(404);
    expect((await ana.req('DELETE', `/posts/${body.data.id}`)).status).toBe(204);
    expect((await anon(`/posts/${body.data.id}`)).status).toBe(404);
  });

  it('las publicaciones "solo seguidores" solo las ven quienes siguen al autor', async () => {
    const ana = await person('soc-f-ana');
    const beto = await person('soc-f-beto');
    const { body } = await ana.json('POST', '/posts', { body: 'solo para seguidores', visibility: 'followers' });
    const id = body.data.id;

    expect((await anon(`/posts/${id}`)).status).toBe(404);
    expect((await beto.json('GET', `/posts/${id}`)).status).toBe(404);
    await beto.json('PUT', `/users/${ana.uid}/follow`);
    expect((await beto.json('GET', `/posts/${id}`)).status).toBe(200);
  });

  it('el perfil privado oculta todas sus publicaciones a terceros', async () => {
    const ana = await person('soc-priv-ana');
    const beto = await person('soc-priv-beto');
    const { body } = await ana.json('POST', '/posts', { body: 'secreto' });
    await ana.json('PATCH', '/me/profile', { visibility: 'private' });
    expect((await beto.json('GET', `/posts/${body.data.id}`)).status).toBe(404);
    expect((await ana.json('GET', `/posts/${body.data.id}`)).status).toBe(200);
  });

  it('el feed "siguiendo" muestra lo propio y lo de quienes sigo', async () => {
    const yo = await person('soc-fol-yo');
    const amiga = await person('soc-fol-amiga');
    const otra = await person('soc-fol-otra');
    await yo.json('PUT', `/users/${amiga.uid}/follow`);
    const a = (await amiga.json('POST', '/posts', { body: 'de amiga' })).body.data.id;
    const o = (await otra.json('POST', '/posts', { body: 'de otra' })).body.data.id;
    const m = (await yo.json('POST', '/posts', { body: 'mío' })).body.data.id;

    const ids = (await yo.json('GET', '/posts?scope=following&limit=50')).body.data.map((p: any) => p.id);
    expect(ids).toContain(a);
    expect(ids).toContain(m);
    expect(ids).not.toContain(o);
    expect((await anon('/posts?scope=following')).status).toBe(401);
  });

  it('pagina el feed sin repetir ni saltar', async () => {
    const pag = await person('soc-pag');
    for (let i = 0; i < 5; i++) await pag.json('POST', '/posts', { body: `n${i}` });
    const p1 = (await anon(`/posts?author=${pag.uid}&limit=2`)).body;
    const p2 = (await anon(`/posts?author=${pag.uid}&limit=2&cursor=${p1.nextCursor}`)).body;
    const p3 = (await anon(`/posts?author=${pag.uid}&limit=2&cursor=${p2.nextCursor}`)).body;
    const all = [...p1.data, ...p2.data, ...p3.data].map((p: any) => p.body);
    expect(all).toEqual(['n4', 'n3', 'n2', 'n1', 'n0']);
    expect(p3.nextCursor).toBeNull();
  });
});

describe('me gusta, guardados y comentarios', () => {
  it('me gusta es idempotente, cuenta bien y notifica al autor una vez', async () => {
    const ana = await person('soc-like-ana');
    const beto = await person('soc-like-beto');
    const id = (await ana.json('POST', '/posts', { body: 'foto del cisne' })).body.data.id;

    await beto.json('PUT', `/posts/${id}/like`);
    const again = await beto.json('PUT', `/posts/${id}/like`);
    expect(again.body.data).toMatchObject({ likeCount: 1, likedByMe: true });

    const notes = (await ana.json('GET', '/me/notifications')).body.data;
    expect(notes.filter((n: any) => n.type === 'reaction')).toHaveLength(1);

    const un = await beto.json('DELETE', `/posts/${id}/like`);
    expect(un.body.data).toMatchObject({ likeCount: 0, likedByMe: false });
  });

  it('dar me gusta a la propia publicación no genera notificación', async () => {
    const ana = await person('soc-self-like');
    const id = (await ana.json('POST', '/posts', { body: 'mío' })).body.data.id;
    await ana.json('PUT', `/posts/${id}/like`);
    expect((await ana.json('GET', '/me/notifications')).body.data).toHaveLength(0);
  });

  it('guardar una publicación la muestra en "guardados"', async () => {
    const ana = await person('soc-bm-ana');
    const beto = await person('soc-bm-beto');
    const id = (await ana.json('POST', '/posts', { body: 'útil' })).body.data.id;
    await beto.req('PUT', `/posts/${id}/bookmark`);
    const saved = (await beto.json('GET', '/posts?scope=bookmarks')).body.data;
    expect(saved.map((p: any) => p.id)).toEqual([id]);
  });

  it('comentar, listar en orden y borrar (autor del comentario o de la publicación)', async () => {
    const ana = await person('soc-cm-ana');
    const beto = await person('soc-cm-beto');
    const caro = await person('soc-cm-caro');
    const id = (await ana.json('POST', '/posts', { body: 'hilo' })).body.data.id;

    const c1 = (await beto.json('POST', `/posts/${id}/comments`, { body: 'primero' })).body.data.id;
    const c2 = (await caro.json('POST', `/posts/${id}/comments`, { body: 'segundo' })).body.data.id;
    const list = (await anon(`/posts/${id}/comments`)).body.data.map((c: any) => c.body);
    expect(list).toEqual(['primero', 'segundo']);
    expect((await anon(`/posts/${id}`)).body.data.commentCount).toBe(2);

    expect((await caro.req('DELETE', `/comments/${c1}`)).status).toBe(404); // ni autora del comentario ni de la publicación
    expect((await ana.req('DELETE', `/comments/${c1}`)).status).toBe(204); // autora de la publicación
    expect((await caro.req('DELETE', `/comments/${c2}`)).status).toBe(204); // autora del comentario
    expect((await anon(`/posts/${id}`)).body.data.commentCount).toBe(0);
  });

  it('no se puede comentar una publicación que no se puede ver', async () => {
    const ana = await person('soc-cmv-ana');
    const beto = await person('soc-cmv-beto');
    const id = (await ana.json('POST', '/posts', { body: 'seguidores', visibility: 'followers' })).body.data.id;
    expect((await beto.json('POST', `/posts/${id}/comments`, { body: 'hola' })).status).toBe(404);
  });
});

describe('seguir y bloquear', () => {
  it('seguir notifica, cuenta y no permite seguirse a sí mismo', async () => {
    const ana = await person('soc-follow-ana');
    const beto = await person('soc-follow-beto');
    const res = await beto.json('PUT', `/users/${ana.uid}/follow`);
    expect(res.body.data).toMatchObject({ following: true, counts: { followers: 1 } });
    expect((await beto.json('PUT', `/users/${beto.uid}/follow`)).status).toBe(400);
    expect((await ana.json('GET', '/me/followers')).body.data.map((p: any) => p.id)).toEqual([beto.uid]);
    expect((await ana.json('GET', '/me/notifications')).body.data[0]).toMatchObject({ type: 'follow', actor: { id: beto.uid } });
  });

  it('bloquear corta el seguimiento, oculta publicaciones y perfil, e impide seguir', async () => {
    const ana = await person('soc-block-ana');
    const beto = await person('soc-block-beto');
    await beto.json('PUT', `/users/${ana.uid}/follow`);
    const id = (await ana.json('POST', '/posts', { body: 'visible antes del bloqueo' })).body.data.id;

    expect((await ana.req('PUT', `/users/${beto.uid}/block`)).status).toBe(204);
    expect((await beto.json('GET', `/posts/${id}`)).status).toBe(404);
    expect((await beto.json('GET', `/users/${ana.uid}`)).status).toBe(404);
    expect((await beto.json('PUT', `/users/${ana.uid}/follow`)).status).toBe(404);
    expect((await ana.json('GET', '/me/followers')).body.data).toHaveLength(0);

    await ana.req('DELETE', `/users/${beto.uid}/block`);
    expect((await beto.json('GET', `/posts/${id}`)).status).toBe(200);
  });

  it('el resumen de una persona respeta la privacidad del perfil', async () => {
    const ana = await person('soc-sum-ana');
    const beto = await person('soc-sum-beto');
    await ana.json('PATCH', '/me/profile', { fullName: 'Ana', bio: 'bio privada', visibility: 'followers' });
    const before = (await beto.json('GET', `/users/${ana.uid}`)).body.data;
    expect(before).toMatchObject({ restricted: true, profile: null });
    await beto.json('PUT', `/users/${ana.uid}/follow`);
    const after = (await beto.json('GET', `/users/${ana.uid}`)).body.data;
    expect(after.profile.bio).toBe('bio privada');
  });
});

describe('comunidades', () => {
  it('crear, unirse, publicar como miembro y salir', async () => {
    const ana = await person('soc-com-ana');
    const beto = await person('soc-com-beto');
    const created = await ana.json('POST', '/communities', { name: 'Aves de Angachilla', slug: 'aves-angachilla', wetland: 'Angachilla' });
    expect(created.status).toBe(201);
    expect(created.body.data).toMatchObject({ memberCount: 1, myRole: 'owner' });

    expect((await ana.json('POST', '/communities', { name: 'Otra', slug: 'aves-angachilla' })).status).toBe(409);

    expect((await beto.json('POST', '/posts', { body: 'hola grupo', communitySlug: 'aves-angachilla' })).status).toBe(400);
    const joined = await beto.json('PUT', '/communities/aves-angachilla/membership');
    expect(joined.body.data).toMatchObject({ memberCount: 2, myRole: 'member' });
    expect((await beto.json('POST', '/posts', { body: 'hola grupo', communitySlug: 'aves-angachilla' })).status).toBe(201);
    expect((await anon('/posts?community=aves-angachilla')).body.data).toHaveLength(1);

    expect((await ana.json('DELETE', '/communities/aves-angachilla/membership')).status).toBe(409);
    expect((await beto.json('DELETE', '/communities/aves-angachilla/membership')).body.data.memberCount).toBe(1);
  });

  it('busca por nombre tratando los comodines como texto', async () => {
    const ana = await person('soc-com-q');
    await ana.json('POST', '/communities', { name: 'Hongos 100% del sur', slug: 'hongos-sur' });
    await ana.json('POST', '/communities', { name: 'Ranas de Valdivia', slug: 'ranas-valdivia' });
    const res = (await anon(`/communities?q=${encodeURIComponent('100%')}`)).body.data.map((c: any) => c.slug);
    expect(res).toEqual(['hongos-sur']);
    expect((await ana.json('GET', '/communities?mine=1&limit=50')).body.data.length).toBeGreaterThanOrEqual(2);
  });
});

describe('mensajes privados', () => {
  it('conversación entre dos personas: solo ellas la ven', async () => {
    const ana = await person('soc-msg-ana');
    const beto = await person('soc-msg-beto');
    const caro = await person('soc-msg-caro');
    const { body } = await ana.json('POST', '/conversations', { userId: beto.uid });
    const convId = body.data.id;
    // Reabrir devuelve la misma conversación (también desde el otro lado).
    expect((await beto.json('POST', '/conversations', { userId: ana.uid })).body.data.id).toBe(convId);

    await ana.json('POST', `/conversations/${convId}/messages`, { body: '¿Viste el huillín?' });
    await beto.json('POST', `/conversations/${convId}/messages`, { body: '¡Sí, en el río Calle-Calle!' });

    const msgs = (await ana.json('GET', `/conversations/${convId}/messages`)).body.data;
    expect(msgs.map((m: any) => [m.body, m.mine])).toEqual([
      ['¡Sí, en el río Calle-Calle!', false],
      ['¿Viste el huillín?', true],
    ]);
    expect((await caro.json('GET', `/conversations/${convId}/messages`)).status).toBe(404);
    expect((await caro.json('POST', `/conversations/${convId}/messages`, { body: 'intrusa' })).status).toBe(404);

    const list = (await beto.json('GET', '/conversations')).body.data;
    expect(list[0]).toMatchObject({ id: convId, unread: 1, with: { id: ana.uid } });
    await beto.req('POST', `/conversations/${convId}/read`);
    expect((await beto.json('GET', '/conversations')).body.data[0].unread).toBe(0);
  });

  it('el bloqueo impide abrir conversación y enviar mensajes', async () => {
    const ana = await person('soc-msgb-ana');
    const beto = await person('soc-msgb-beto');
    const convId = (await ana.json('POST', '/conversations', { userId: beto.uid })).body.data.id;
    await beto.req('PUT', `/users/${ana.uid}/block`);
    expect((await ana.json('POST', `/conversations/${convId}/messages`, { body: 'hola' })).status).toBe(403);
    expect((await ana.json('POST', '/conversations', { userId: beto.uid })).status).toBe(404);
  });
});

describe('notificaciones y denuncias', () => {
  it('marca como leídas solo las propias', async () => {
    const ana = await person('soc-not-ana');
    const beto = await person('soc-not-beto');
    await beto.json('PUT', `/users/${ana.uid}/follow`);
    expect((await ana.json('GET', '/me/notifications/unread-count')).body.data.unread).toBe(1);
    const noteId = (await ana.json('GET', '/me/notifications')).body.data[0].id;

    await beto.req('POST', '/me/notifications/read', { ids: [noteId] }); // de otra persona: sin efecto
    expect((await ana.json('GET', '/me/notifications/unread-count')).body.data.unread).toBe(1);
    await ana.req('POST', '/me/notifications/read', {});
    expect((await ana.json('GET', '/me/notifications/unread-count')).body.data.unread).toBe(0);
  });

  it('denunciar es idempotente y valida el motivo', async () => {
    const ana = await person('soc-rep-ana');
    expect((await ana.json('POST', '/reports', { targetType: 'post', targetId: 'abc', reason: 'spam' })).status).toBe(202);
    expect((await ana.json('POST', '/reports', { targetType: 'post', targetId: 'abc', reason: 'spam' })).status).toBe(202);
    expect((await ana.json('POST', '/reports', { targetType: 'post', targetId: 'abc', reason: 'me cae mal' })).status).toBe(400);
    expect((await ana.json('POST', '/reports', { targetType: 'user', targetId: ana.uid, reason: 'other' })).status).toBe(400);
  });
});
