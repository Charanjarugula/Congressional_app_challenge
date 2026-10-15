(function () {
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* Reveal on scroll, and run looping illustrations only while visible */
  var els = document.querySelectorAll('.reveal, .loop');
  if (reduce || !('IntersectionObserver' in window)) {
    els.forEach(function (e) { e.classList.add('in', 'play'); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        var t = en.target;
        if (t.classList.contains('loop')) t.classList.toggle('play', en.isIntersecting);
        if (en.isIntersecting && t.classList.contains('reveal')) t.classList.add('in');
      });
    }, { rootMargin: '0px 0px 35% 0px' });
    els.forEach(function (e) { io.observe(e); });
  }
  if (reduce) return;

  /* Hero phone leans toward the pointer */
  var tilt = document.querySelector('[data-tilt]');
  if (tilt && window.matchMedia('(pointer: fine)').matches) {
    window.addEventListener('pointermove', function (e) {
      var x = e.clientX / window.innerWidth - 0.5, y = e.clientY / window.innerHeight - 0.5;
      tilt.style.transform = 'perspective(900px) rotateY(' + (x * 10).toFixed(2) + 'deg) rotateX(' + (-y * 8).toFixed(2) + 'deg)';
    }, { passive: true });
  }

  /* Parallax for elements with data-x / data-y / data-r */
  var movers = Array.prototype.map.call(document.querySelectorAll('[data-x],[data-y],[data-r]'), function (el) {
    return { el: el, box: el.closest('[data-scroll]') || el, x: +el.dataset.x || 0, y: +el.dataset.y || 0, r: +el.dataset.r || 0 };
  });

  /* The rally: one ball bounces from card to card as you scroll through "How it works" */
  var how = document.querySelector('.how');
  var svg = how && how.querySelector('.rally-svg');
  var path = svg && svg.querySelector('.rally-path');
  var ballG = svg && svg.querySelector('.rally-ball');
  var body = svg && svg.querySelector('.rally-body');
  var shadow = svg && svg.querySelector('.rally-shadow');
  var fx = svg && svg.querySelector('.rally-fx');
  var ghosts = svg ? Array.prototype.slice.call(svg.querySelectorAll('.ghost')) : [];
  var lastLen = 0, speed = 0;
  function burst(x, y) {
    if (!fx) return;
    var ns = 'http://www.w3.org/2000/svg';
    ['burst', 'burst b2'].forEach(function (cls) {
      var c = document.createElementNS(ns, 'circle');
      c.setAttribute('cx', x); c.setAttribute('cy', y + AIR); c.setAttribute('r', 10); c.setAttribute('class', cls);
      fx.appendChild(c); setTimeout(function () { c.remove(); }, 900);
    });
    for (var i = 0; i < 6; i++) {
      var d = document.createElementNS(ns, 'circle'), ang = Math.PI * (1.05 + i * 0.18);
      d.setAttribute('cx', x); d.setAttribute('cy', y + AIR); d.setAttribute('r', 3.5); d.setAttribute('class', 'spark');
      d.style.setProperty('--dx', (Math.cos(ang) * 46).toFixed(1) + 'px'); d.style.setProperty('--dy', (Math.sin(ang) * 34).toFixed(1) + 'px');
      fx.appendChild(d); setTimeout(function (n) { return function () { n.remove(); }; }(d), 800);
    }
  }
  var lands = how ? Array.prototype.slice.call(how.querySelectorAll('[data-land]')) : [];
  var total = 0, landLens = [], landY = [], allY = [];
  var AIR = 15; /* ball centre above the contact point: radius 21 squashed to about 0.7 */
  function buildPath() {
    if (!how || !path) return;
    var hr = how.getBoundingClientRect();
    svg.setAttribute('viewBox', '0 0 ' + hr.width + ' ' + hr.height);
    svg.setAttribute('width', hr.width); svg.setAttribute('height', hr.height);
    var pts = [{ x: hr.width / 2, y: -40 }];
    lands.forEach(function (el) {
      /* layout position, ignoring the reveal transform, so the path matches where the card settles */
      /* the exact spot on the graphic's top edge, after its resting tilt, so the squashed ball touches it */
      var card = el.querySelector('.lift') || el, x = 0, y = 0, n = card;
      while (n && n !== how) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent; }
      var art = card.querySelector('svg'), h = (card.dataset.hit || '220 0 440').split(' ').map(Number);
      var sw = art.clientWidth || card.offsetWidth, sc = sw / h[2];
      var px = x + (card.offsetWidth - sw) / 2 + h[0] * sc, py = y + h[1] * sc;
      var cx = x + card.offsetWidth / 2, cy = y + card.offsetHeight / 2, a = (+card.dataset.tiltDeg || 0) * Math.PI / 180;
      var rx = cx + (px - cx) * Math.cos(a) - (py - cy) * Math.sin(a), ry = cy + (px - cx) * Math.sin(a) + (py - cy) * Math.cos(a);
      pts.push({ x: rx, y: ry - AIR });
    });
    var d = 'M' + pts[0].x + ' ' + pts[0].y;
    for (var i = 1; i < pts.length; i++) {
      var a = pts[i - 1], b = pts[i];
      var cx = (a.x + b.x) / 2, cy = Math.min(a.y, b.y) - Math.max(140, Math.abs(b.y - a.y) * 0.35);
      d += ' Q' + cx.toFixed(1) + ' ' + cy.toFixed(1) + ' ' + b.x.toFixed(1) + ' ' + b.y.toFixed(1);
    }
    path.setAttribute('d', d);
    total = path.getTotalLength();
    landLens = []; landY = pts.slice(1).map(function (p) { return p.y; }); allY = pts.map(function (p) { return p.y; });
    var segs = d.split(' Q').length - 1, acc = 0, tmp = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    var parts = d.split(' Q');
    for (var k = 1; k <= segs; k++) {
      tmp.setAttribute('d', parts.slice(0, k + 1).join(' Q'));
      landLens.push(tmp.getTotalLength());
    }
    path.style.strokeDasharray = total; 
  }
  function rally() {
    if (!total) return;
    var hr = how.getBoundingClientRect(), vh = window.innerHeight;
    /* the ball reaches each bounce point as that point crosses the middle of the screen */
    var c = vh * 0.5 - hr.top, lens = [0].concat(landLens), len = 0;
    if (c <= allY[0]) len = 0;
    else if (c >= allY[allY.length - 1]) len = lens[lens.length - 1];
    else for (var k = 1; k < allY.length; k++) {
      if (c <= allY[k]) { var t = (c - allY[k - 1]) / (allY[k] - allY[k - 1]); len = lens[k - 1] + Math.max(0, Math.min(1, t)) * (lens[k] - lens[k - 1]); break; }
    }
    var p = len / lens[lens.length - 1];
    var pt = path.getPointAtLength(len);
    path.style.strokeDashoffset = total - len;
    ballG.setAttribute('transform', 'translate(' + pt.x.toFixed(1) + ' ' + pt.y.toFixed(1) + ')');
    /* squash near each landing, shadow tracks the ground under the next landing */
    var near = 1e9, idx = 0;
    landLens.forEach(function (L, i) { var dd = Math.abs(L - len); if (dd < near) { near = dd; idx = i; } });
    var squash = Math.max(0, 1 - near / 45);
    body.setAttribute('transform', 'rotate(' + (len * 1.2).toFixed(1) + ') scale(' + (1 + squash * 0.3).toFixed(3) + ' ' + (1 - squash * 0.32).toFixed(3) + ')');
    var prevLen = lastLen;
    speed = speed * 0.7 + Math.abs(len - lastLen) * 0.3; lastLen = len;
    var trail = Math.min(1, speed / 28);
    ghosts.forEach(function (g, i) {
      var gp = path.getPointAtLength(Math.max(0, len - (i + 1) * (12 + speed * 0.8)));
      g.setAttribute('cx', gp.x.toFixed(1)); g.setAttribute('cy', gp.y.toFixed(1));
      g.style.opacity = (trail * (0.32 - i * 0.09)).toFixed(2);
    });
    var nextIdx = 0; while (nextIdx < landLens.length - 1 && landLens[nextIdx] < len) nextIdx++;
    if (near < 60) nextIdx = idx;
    var groundY = landY[nextIdx] + AIR - pt.y;
    shadow.setAttribute('cy', groundY.toFixed(1));
    var lift = Math.min(1, Math.max(0, groundY / 160));
    shadow.setAttribute('rx', (16 * (1 - lift * 0.6)).toFixed(1));
    shadow.style.opacity = (0.28 * (1 - lift) * (1 - lift)).toFixed(2);
    ballG.style.opacity = p <= 0 ? 0 : 1;
    landLens.forEach(function (L, i) {
      if (prevLen !== len && ((prevLen < L && len >= L) || (prevLen > L && len <= L))) {
        var art = lands[i]; art.classList.remove('hit'); void art.offsetWidth; art.classList.add('hit');
        var lp = path.getPointAtLength(L); burst(lp.x, lp.y);
      }
    });
  }

  var ticking = false;
  function frame() {
    ticking = false;
    var vh = window.innerHeight;
    movers.forEach(function (m) {
      var r = m.box.getBoundingClientRect();
      if (r.bottom < -200 || r.top > vh + 200) return;
      var o = Math.max(-1, Math.min(1, ((vh - r.top) / (vh + r.height) - 0.5) * 2));
      m.el.style.transform = 'translate3d(' + (m.x * o).toFixed(1) + 'px,' + (m.y * o).toFixed(1) + 'px,0) rotate(' + (m.r * o).toFixed(1) + 'deg)';
    });
    rally();
  }
  function onScroll() { if (!ticking) { ticking = true; requestAnimationFrame(frame); } }
  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', function () { buildPath(); frame(); });
  window.addEventListener('load', function () { buildPath(); frame(); });
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { buildPath(); frame(); });
  buildPath(); frame();
})();
