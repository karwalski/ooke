/**
 * hello.js — Stub island module for testing the ooke-islands loader.
 *
 * Returns simple HTML so the hydration pipeline can be verified
 * before real WASM islands are compiled.
 */
export default function render() {
  return '<p>Hello from island</p>';
}

export { render };
