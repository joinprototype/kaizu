// Kaizu: finds login fields, and fills one with a login from the Passwords app.
//
// Runs in its own content world in every frame, out of the page's reach.
// When a login field gets focus, it tells Kaizu where the field is, so
// Kaizu can show its key button there. A login the user picks in Kaizu's
// picker comes back through `__kaizuFillLogin`, which fills the field's
// form, and only when the frame is still on the origin it was picked for.
// The script never reads what is typed into a field.
(() => {
  'use strict';
  const handler = window.webkit?.messageHandlers?.kaizuPasswords;
  if (!handler) return;

  const isInput = (element) => element?.localName === 'input';
  const isPassword = (element) => isInput(element) && element.type === 'password';
  const isTextual = (element) => isInput(element) && ['text', 'email', 'tel'].includes(element.type);
  const isEditable = (element) => !element.disabled && !element.readOnly;
  const isVisible = (element) => {
    const box = element.getBoundingClientRect();
    return box.width > 1 && box.height > 1 && getComputedStyle(element).visibility !== 'hidden';
  };
  const tokens = (element) => (element.getAttribute('autocomplete') || '').toLowerCase().split(/\s+/);
  const scopeOf = (element) => element.form ?? element.closest('form') ?? document;
  const passwordsIn = (scope) => [...scope.querySelectorAll('input[type=password]')]
    .filter((field) => isEditable(field) && isVisible(field) && !tokens(field).includes('new-password'));
  // Words a username field tends to be named or labelled with, for
  // username-first sign-ins (Google, Apple, Microsoft) whose page has no
  // password field yet.
  const usernameHint = /user|e-?mail|login|account|identifier|phone/i;

  const isUsername = (element) => {
    if (!isTextual(element) || !isEditable(element)) return false;
    const autocomplete = tokens(element);
    if (autocomplete.includes('username') || autocomplete.includes('email')) return true;
    if (autocomplete.includes('one-time-code') || autocomplete.includes('off')) return false;
    if (passwordsIn(scopeOf(element)).length) return true;
    const names = [element.name, element.id, element.placeholder, element.getAttribute('aria-label')].join(' ');
    return element.type === 'email' || usernameHint.test(names);
  };
  const isLogin = (element) => (isPassword(element) && isEditable(element) && !tokens(element).includes('new-password'))
    || isUsername(element);

  // The login field that has focus, if any, and the last one that had:
  // opening Kaizu's picker takes focus from the page before the fill.
  let field = null;
  let last = null;
  let scheduled = 0;

  const report = () => {
    scheduled = 0;
    if (!field) return;
    if (!field.isConnected || !isVisible(field)) {
      leave();
      return;
    }
    const box = field.getBoundingClientRect();
    handler.postMessage({
      type: 'focus', x: box.left, y: box.top, width: box.width, height: box.height,
      password: isPassword(field),
    });
  };
  const follow = () => {
    if (field && !scheduled) scheduled = requestAnimationFrame(report);
  };
  const leave = () => {
    if (!field) return;
    field = null;
    handler.postMessage({ type: 'blur' });
  };

  document.addEventListener('focusin', (event) => {
    // Inside a shadow root, the event names the host; the field is first on the path.
    const target = event.composedPath()[0];
    if (isLogin(target)) {
      field = last = target;
      report();
    } else {
      leave();
    }
  }, true);
  document.addEventListener('focusout', (event) => {
    if (event.composedPath()[0] === field) leave();
  }, true);
  addEventListener('scroll', follow, true);
  addEventListener('resize', follow);
  addEventListener('pagehide', leave);

  // The first login field of the page's first login form (the username,
  // usually), or of the page.
  const firstLoginField = () => {
    const password = passwordsIn(document)[0];
    const scope = password ? scopeOf(password) : document;
    return [...scope.querySelectorAll('input')].find((element) => isVisible(element) && isLogin(element)) ?? password;
  };

  // For the menu command: gives the page's first login field focus, which
  // reports it like a click would. False when there's none.
  globalThis.__kaizuFocusLogin = () => {
    if (field?.isConnected) {
      report();
      return true;
    }
    const found = last?.isConnected ? last : firstLoginField();
    found?.focus();
    return !!found;
  };

  const put = (element, value) => {
    element.focus();
    // From this world, the page's own bookkeeping of the field's value
    // (React's, for one) still holds the old one, so the events below
    // read as the user's edit.
    element.value = value;
    element.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
    element.dispatchEvent(new Event('change', { bubbles: true }));
  };

  // Fills the focused field's form. Answers what it filled: "both",
  // "password", "username" (a username-first page), or why it didn't:
  // "origin" (the frame has moved on) or "none".
  globalThis.__kaizuFillLogin = (username, password, origin) => {
    if (location.origin !== origin) return 'origin';
    const target = last?.isConnected ? last : firstLoginField();
    if (!target) return 'none';
    const scope = scopeOf(target);
    const passwordField = isPassword(target) ? target : passwordsIn(scope)[0] ?? null;
    let usernameField = isPassword(target) ? null : target;
    if (!usernameField && passwordField) {
      // The nearest visible text field before the password field.
      const inputs = [...scope.querySelectorAll('input')].filter(isVisible);
      usernameField = inputs.slice(0, inputs.indexOf(passwordField)).reverse()
        .find((element) => isTextual(element) && isEditable(element)) ?? null;
    }
    if (usernameField && username) put(usernameField, username);
    if (passwordField && password) put(passwordField, password);
    if (passwordField) {
      passwordField.focus();
      return usernameField && username ? 'both' : 'password';
    }
    return usernameField ? 'username' : 'none';
  };
})();
