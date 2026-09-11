/*
 * Generic Chart.js auto-initializer for OKAPI Survey Admin dashboards.
 * Usage: add a <canvas> with data-chart-type="bar|horizontalBar|pie|doughnut|line"
 * plus data-labels='[...]' and data-values='[...]' (JSON-encoded via Jinja |tojson).
 * Optional: data-values2 (second dataset, grouped bar), data-series-name,
 * data-series2-name, data-horizontal="1", data-single-color="1".
 */
(function () {
  var PALETTE = [
    '#6B1F1F', '#1F5A8F', '#C9922B', '#1F4A2E', '#8a2c2c',
    '#4a7fb5', '#dba13f', '#3f7a55', '#9c4b4b', '#5f8fc0',
    '#b5842a', '#2e6b46',
  ];

  function parseJSONAttr(el, name, fallback) {
    var raw = el.getAttribute(name);
    if (!raw) return fallback;
    try {
      return JSON.parse(raw);
    } catch (e) {
      return fallback;
    }
  }

  function hexToRgba(hex, alpha) {
    var h = hex.replace('#', '');
    var r = parseInt(h.substring(0, 2), 16);
    var g = parseInt(h.substring(2, 4), 16);
    var b = parseInt(h.substring(4, 6), 16);
    return 'rgba(' + r + ',' + g + ',' + b + ',' + alpha + ')';
  }

  function colorList(n, alpha) {
    var out = [];
    for (var i = 0; i < n; i++) {
      out.push(hexToRgba(PALETTE[i % PALETTE.length], alpha));
    }
    return out;
  }

  function initChart(canvas) {
    var rawType = canvas.getAttribute('data-chart-type') || 'bar';
    var horizontal = canvas.getAttribute('data-horizontal') === '1' || rawType === 'horizontalBar';
    var chartType = rawType === 'horizontalBar' ? 'bar' : rawType;

    var labels = parseJSONAttr(canvas, 'data-labels', []);
    var values = parseJSONAttr(canvas, 'data-values', []);
    var values2 = parseJSONAttr(canvas, 'data-values2', null);
    var series1 = canvas.getAttribute('data-series-name') || '';
    var series2 = canvas.getAttribute('data-series2-name') || '';
    var singleColor = canvas.getAttribute('data-single-color') === '1';

    var datasets;
    var isCircular = chartType === 'pie' || chartType === 'doughnut';

    if (values2) {
      datasets = [
        {
          label: series1,
          data: values,
          backgroundColor: hexToRgba(PALETTE[0], 0.85),
          borderRadius: 4,
          maxBarThickness: 34,
        },
        {
          label: series2,
          data: values2,
          backgroundColor: hexToRgba(PALETTE[1], 0.85),
          borderRadius: 4,
          maxBarThickness: 34,
        },
      ];
    } else if (isCircular) {
      datasets = [
        {
          data: values,
          backgroundColor: colorList(values.length, 0.88),
          borderWidth: 2,
          borderColor: '#fff',
        },
      ];
    } else if (chartType === 'line') {
      datasets = [
        {
          label: series1 || 'Valeur',
          data: values,
          borderColor: PALETTE[0],
          backgroundColor: hexToRgba(PALETTE[0], 0.14),
          fill: true,
          tension: 0.35,
          pointRadius: 3,
          pointBackgroundColor: PALETTE[0],
        },
      ];
    } else {
      datasets = [
        {
          label: series1 || 'Valeur',
          data: values,
          backgroundColor: singleColor
            ? hexToRgba(PALETTE[0], 0.85)
            : colorList(values.length, 0.85),
          borderRadius: 4,
          maxBarThickness: 38,
        },
      ];
    }

    var showLegend = isCircular || !!values2;

    /* eslint-disable no-undef */
    new Chart(canvas.getContext('2d'), {
      type: chartType,
      data: { labels: labels, datasets: datasets },
      options: {
        indexAxis: horizontal ? 'y' : 'x',
        responsive: true,
        maintainAspectRatio: false,
        animation: { duration: 650 },
        plugins: {
          legend: {
            display: showLegend,
            position: 'bottom',
            labels: { font: { size: 11 }, boxWidth: 12, padding: 10 },
          },
          tooltip: { enabled: true },
        },
        scales: isCircular
          ? {}
          : {
              x: {
                ticks: { font: { size: 10.5 } },
                grid: { display: !horizontal, color: '#eee' },
                beginAtZero: !horizontal,
              },
              y: {
                ticks: { font: { size: 10.5 } },
                grid: { display: horizontal, color: '#eee' },
                beginAtZero: horizontal,
              },
            },
      },
    });
    /* eslint-enable no-undef */
  }

  function initTabs() {
    document.querySelectorAll('[data-tabgroup]').forEach(function (group) {
      var name = group.getAttribute('data-tabgroup');
      var buttons = group.querySelectorAll('.panel-tab-btn');
      buttons.forEach(function (btn) {
        btn.addEventListener('click', function () {
          var target = btn.getAttribute('data-target');
          buttons.forEach(function (b) { b.classList.remove('active'); });
          btn.classList.add('active');
          document.querySelectorAll('[data-tabview="' + name + '"]').forEach(function (view) {
            view.classList.toggle('active', view.getAttribute('data-view-id') === target);
          });
        });
      });
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    initTabs();
    if (typeof Chart === 'undefined') return;
    var canvases = document.querySelectorAll('canvas[data-chart-type]');
    canvases.forEach(function (c) {
      try {
        initChart(c);
      } catch (e) {
        /* Fail silently per-chart so one bad dataset doesn't break the page */
        if (window.console) console.warn('Chart init failed', e);
      }
    });
  });
})();
