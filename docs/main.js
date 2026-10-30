// FirestoreRestDocuments site interactions
(function () {
  'use strict';

  // Nav scroll state
  const nav = document.getElementById('nav');
  let lastY = 0;
  function onScroll() {
    const y = window.scrollY;
    nav.classList.toggle('scrolled', y > 8);
    lastY = y;
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  // Reveal on scroll
  const revealEls = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) {
          e.target.classList.add('in');
          io.unobserve(e.target);
        }
      });
    }, { threshold: 0, rootMargin: '0px 0px -40px 0px' });
    revealEls.forEach((el) => io.observe(el));
    // Fallback: never leave content hidden if observer never fires
    setTimeout(() => revealEls.forEach((el) => el.classList.add('in')), 1200);
  } else {
    revealEls.forEach((el) => el.classList.add('in'));
  }

  // Stagger reveal children within grids
  document.querySelectorAll('.feature-grid, .styles-grid, .layers, .products').forEach((g) => {
    Array.from(g.children).forEach((c, i) => {
      c.style.setProperty('--i', i);
      c.classList.add('reveal-stagger');
    });
  });

  // Code tabs
  const codeTabs = document.getElementById('codeTabs');
  if (codeTabs) {
    const tabs = codeTabs.querySelectorAll('.tab-bar .tab');
    const panels = codeTabs.querySelectorAll('.tab-panel');
    tabs.forEach((t) => {
      t.addEventListener('click', () => {
        const name = t.dataset.tab;
        tabs.forEach((x) => x.classList.toggle('active', x === t));
        panels.forEach((p) => p.classList.toggle('active', p.dataset.panel === name));
      });
    });
  }

  // Install tabs
  document.querySelectorAll('[data-install]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const name = btn.dataset.install;
      const card = btn.closest('.install-card');
      card.querySelectorAll('[data-install]').forEach((b) => b.classList.toggle('active', b === btn));
      card.querySelectorAll('[data-install-panel]').forEach((p) => p.classList.toggle('active', p.dataset.installPanel === name));
    });
  });

  // Smooth anchor scroll with nav offset
  document.querySelectorAll('a[href^="#"]').forEach((a) => {
    a.addEventListener('click', (e) => {
      const id = a.getAttribute('href');
      if (id === '#' || id.length < 2) return;
      const target = document.querySelector(id);
      if (!target) return;
      e.preventDefault();
      const top = target.getBoundingClientRect().top + window.scrollY - 72;
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      window.scrollTo({ top, behavior: reduce ? 'auto' : 'smooth' });
      // If the link targets an install tab, activate it
      const tabName = a.dataset.installTab;
      if (tabName) {
        const card = document.querySelector('.install-card');
        if (card) {
          const btn = card.querySelector('[data-install="' + tabName + '"]');
          if (btn) btn.click();
        }
      }
    });
  });

  // Hero visual parallax on mouse move (desktop, fine pointer)
  const heroVisual = document.querySelector('.hero-visual');
  if (heroVisual && window.matchMedia('(hover: hover) and (pointer: fine)').matches) {
    const front = heroVisual.querySelector('.doc-card-front');
    const back = heroVisual.querySelector('.doc-card-back');
    heroVisual.addEventListener('mousemove', (e) => {
      const r = heroVisual.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width - 0.5;
      const y = (e.clientY - r.top) / r.height - 0.5;
      if (front) front.style.transform = `rotate(3deg) translate(${x * 12}px, ${y * 12}px)`;
      if (back) back.style.transform = `rotate(-4deg) translate(${x * -8}px, ${y * -8}px)`;
    });
    heroVisual.addEventListener('mouseleave', () => {
      if (front) front.style.transform = '';
      if (back) back.style.transform = '';
    });
  }

  // Typing effect in terminal? keep static — no.

  // Theme toggle
  const themeToggle = document.getElementById('themeToggle');
  const root = document.documentElement;
  function applyTheme(mode) {
    root.classList.remove('light', 'dark');
    if (mode === 'dark') root.classList.add('dark');
    else if (mode === 'light') root.classList.add('light');
  }
  const stored = localStorage.getItem('theme');
  if (stored === 'dark' || (!stored && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
    applyTheme('dark');
  } else if (stored === 'light') {
    applyTheme('light');
  }
  if (themeToggle) {
    themeToggle.addEventListener('click', () => {
      const isDark = root.classList.contains('dark') || (!root.classList.contains('light') && window.matchMedia('(prefers-color-scheme: dark)').matches);
      const next = isDark ? 'light' : 'dark';
      applyTheme(next);
      localStorage.setItem('theme', next);
    });
  }

  // Mobile nav toggle
  const navToggle = document.getElementById('navToggle');
  const navEl = document.getElementById('nav');
  if (navToggle && navEl) {
    navToggle.addEventListener('click', () => {
      const open = navEl.classList.toggle('open');
      navToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    document.querySelectorAll('#navMobile a').forEach((a) => {
      a.addEventListener('click', () => {
        navEl.classList.remove('open');
        navToggle.setAttribute('aria-expanded', 'false');
      });
    });
  }

  // Respect reduced motion for scroll behavior already handled.

  // MCP visual: dynamic connectors that follow nodes (draggable) and wrap across lines
  const mcpVisual = document.querySelector('.mcp-visual');
  if (mcpVisual) {
    const mcpSvg = mcpVisual.querySelector('.mcp-connections');
    const mcpNodes = Array.from(mcpVisual.querySelectorAll('.mcp-node'));
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    function centers() {
      const vr = mcpVisual.getBoundingClientRect();
      return mcpNodes.map((n) => {
        const r = n.getBoundingClientRect();
        return { x: r.left + r.width / 2 - vr.left, y: r.top + r.height / 2 - vr.top };
      });
    }

    function rebuild() {
      if (!mcpSvg) return;
      const c = centers();
      mcpSvg.innerHTML = '';
      const accent = getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#0066cc';
      const accent2 = getComputedStyle(document.documentElement).getPropertyValue('--accent-2').trim() || '#2997ff';

      for (let i = 0; i < c.length - 1; i++) {
        const a = c[i], b = c[i + 1];
        const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
        line.setAttribute('x1', a.x); line.setAttribute('y1', a.y);
        line.setAttribute('x2', b.x); line.setAttribute('y2', b.y);
        line.setAttribute('stroke', accent);
        line.setAttribute('stroke-opacity', '0.9');
        line.setAttribute('stroke-width', '2');
        line.setAttribute('stroke-linecap', 'round');
        mcpSvg.appendChild(line);

        if (!reduceMotion) {
          const pulse = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
          pulse.setAttribute('r', '4');
          pulse.setAttribute('fill', i === 0 ? accent2 : '#ff6b9d');
          const anim = document.createElementNS('http://www.w3.org/2000/svg', 'animateMotion');
          anim.setAttribute('dur', '2s');
          anim.setAttribute('repeatCount', 'indefinite');
          anim.setAttribute('begin', (i === 1 ? '1s' : '0s'));
          anim.setAttribute('path', `M ${b.x} ${b.y} L ${a.x} ${a.y}`);
          pulse.appendChild(anim);
          mcpSvg.appendChild(pulse);
        }
      }
    }

    const initialOffsets = [{ x: 0, y: 0 }, { x: 50, y: 90 }, { x: 60, y: -40 }];
    mcpNodes.forEach((node, i) => {
      const o = initialOffsets[i] || { x: 0, y: 0 };
      node.style.transform = `translate(${o.x}px, ${o.y}px)`;
    });

    let dragging = null;

    mcpNodes.forEach((node) => {
      node.addEventListener('pointerdown', (e) => {
        node.setPointerCapture(e.pointerId);
        dragging = node;
        node._dragStart = { px: e.clientX, py: e.clientY, tx: 0, ty: 0 };
        const m = /translate\(([-\d.]+)px,\s*([-\d.]+)px\)/.exec(node.style.transform || '');
        if (m) { node._dragStart.tx = parseFloat(m[1]); node._dragStart.ty = parseFloat(m[2]); }
        node.style.transition = 'none';
        e.preventDefault();
      });
    });

    window.addEventListener('pointermove', (e) => {
      if (!dragging || !dragging._dragStart) return;
      const dx = e.clientX - dragging._dragStart.px;
      const dy = e.clientY - dragging._dragStart.py;
      dragging.style.transform = `translate(${dragging._dragStart.tx + dx}px, ${dragging._dragStart.ty + dy}px)`;
      rebuild();
    });

    window.addEventListener('pointerup', () => {
      if (dragging) {
        dragging._dragStart = null;
        dragging.style.transition = '';
      }
      dragging = null;
    });

    if ('ResizeObserver' in window) {
      const ro = new ResizeObserver(() => rebuild());
      ro.observe(mcpVisual);
    }
    window.addEventListener('resize', rebuild);
    requestAnimationFrame(() => rebuild());
    setTimeout(rebuild, 1300);
  }
})();
