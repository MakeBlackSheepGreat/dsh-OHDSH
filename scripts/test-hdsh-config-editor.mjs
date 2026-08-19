import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Readable } from 'node:stream';
import { pathToFileURL } from 'node:url';

const pluginPath = path.resolve('entry/src/main/resources/rawfile/dsh/node_modules/hdsh-config-editor/lib/index.js');
const plugin = await import(pathToFileURL(pluginPath).href);
const tempDir = mkdtempSync(path.join(tmpdir(), 'hdsh-config-editor-'));
const settingsPath = path.join(tempDir, 'settings.yaml');
writeFileSync(settingsPath, 'general:\n  locale: zh\n', 'utf8');

const routes = new Map();
const host = {
  webServer: {
    register(definition) {
      const key = definition.path + ':' + definition.handler.name + ':' + routes.size;
      routes.set(key, definition.handler);
      return () => routes.delete(key);
    }
  },
  settings: {
    async prepareDocument() {
      return settingsPath;
    }
  },
  effect(callback) {
    return callback();
  }
};

plugin.apply({
  inject(names, callback) {
    assert.deepEqual(names, ['webServer', 'settings']);
    callback(host);
  }
});

const handlers = [...routes.values()];
assert.equal(handlers.length, 2, 'editor must register read and write routes');
const readHandler = handlers[0];
const writeHandler = handlers[1];

function createResponse() {
  return {
    status: 0,
    body: '',
    writeHead(status) {
      this.status = status;
    },
    end(body = '') {
      this.body = String(body);
    }
  };
}

function createRequest(method, body, origin = 'http://127.0.0.1:3080') {
  const chunks = body === undefined ? [] : [Buffer.from(JSON.stringify(body), 'utf8')];
  const request = Readable.from(chunks);
  request.method = method;
  request.headers = { host: '127.0.0.1:3080', origin };
  return request;
}

async function invoke(handler, method, body, origin) {
  const response = createResponse();
  await handler(createRequest(method, body, origin), response);
  return { status: response.status, body: JSON.parse(response.body) };
}

try {
  const initial = await invoke(readHandler, 'GET');
  assert.equal(initial.status, 200);
  assert.equal(initial.body.ok, true);
  assert.equal(typeof initial.body.revision, 'string');

  const saved = await invoke(writeHandler, 'POST', {
    content: 'general:\n  locale: en\n',
    revision: initial.body.revision
  });
  assert.equal(saved.status, 200);
  assert.equal(saved.body.ok, true);
  assert.equal(readFileSync(settingsPath, 'utf8'), 'general:\n  locale: en\n');

  const stale = await invoke(writeHandler, 'POST', {
    content: 'general:\n  locale: zh\n',
    revision: initial.body.revision
  });
  assert.equal(stale.status, 409);
  assert.equal(readFileSync(settingsPath, 'utf8'), 'general:\n  locale: en\n');

  const invalid = await invoke(writeHandler, 'POST', {
    content: 'general: [\n',
    revision: saved.body.revision
  });
  assert.equal(invalid.status, 400);
  assert.equal(readFileSync(settingsPath, 'utf8'), 'general:\n  locale: en\n');

  const rejected = await invoke(readHandler, 'GET', undefined, 'https://untrusted.example');
  assert.equal(rejected.status, 403);
  console.log('hdsh-config-editor route tests passed');
} finally {
  rmSync(tempDir, { recursive: true, force: true });
}
