// /hit?id=<uuid>: point the button at the hit inside the app, and try to open it straight away.
(function () {
  var id = new URLSearchParams(location.search).get('id') || '';
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) return;
  var link = 'courtly://hit/' + id.toLowerCase();
  var button = document.getElementById('open-hit');
  if (button) button.setAttribute('href', link);
  if (/iPhone|iPad|iPod/.test(navigator.userAgent)) setTimeout(function () { location.href = link; }, 400);
})();
