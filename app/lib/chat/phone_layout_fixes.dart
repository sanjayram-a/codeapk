const phoneLayoutFixesJs = '''
(() => {
  const apply = () => {
    let viewport = document.querySelector('meta[name="viewport"]');
    if (!viewport) {
      viewport = document.createElement('meta');
      viewport.setAttribute('name', 'viewport');
      document.head.appendChild(viewport);
    }
    viewport.setAttribute(
      'content',
      'width=device-width, initial-scale=1, viewport-fit=cover',
    );
    if (document.getElementById('pocket-phone-layout')) return;
    const style = document.createElement('style');
    style.id = 'pocket-phone-layout';
    style.textContent = [
      'html, body { max-width: 100vw; overflow-x: hidden; }',
      'textarea, input, select { font-size: 16px !important; }',
    ].join('\\n');
    document.head.appendChild(style);
  };
  if (document.head) {
    apply();
  } else {
    document.addEventListener('DOMContentLoaded', apply, { once: true });
  }
})();
''';
