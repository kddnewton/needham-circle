// Progressive enhancement for the event filters. Without this script the chip
// links and the search form navigate normally; with it, filtering happens via
// AJAX against /events and the URL is kept in sync so views stay shareable.
(function () {
  "use strict";

  var filters = document.querySelector("[data-filters]");
  var results = document.querySelector("[data-events]");
  if (!filters || !results) return;

  var chips = filters.querySelectorAll("[data-source]");
  var search = filters.querySelector("[data-search]");
  var searchTimer = null;

  // Builds the query string from the current chip/search state.
  function queryString() {
    var params = new URLSearchParams();

    var sources = [];
    chips.forEach(function (chip) {
      if (chip.getAttribute("aria-pressed") === "true") {
        sources.push(chip.dataset.source);
      }
    });
    if (sources.length) params.set("source", sources.join(","));

    if (search && search.value.trim()) params.set("q", search.value.trim());

    return params.toString();
  }

  // Fetches the filtered list fragment and swaps it into the results region.
  function refresh() {
    var qs = queryString();
    fetch("/events" + (qs ? "?" + qs : ""), {
      headers: { "X-Requested-With": "fetch" }
    })
      .then(function (response) {
        return response.text();
      })
      .then(function (html) {
        results.innerHTML = html;
      });
  }

  // Pushes the matching "/" URL so the address bar reflects the filters and
  // back/forward works, then refreshes the list.
  function apply() {
    var qs = queryString();
    history.pushState(null, "", qs ? "/?" + qs : "/");
    refresh();
  }

  // Reflects the current URL onto the chips and search box (used on popstate).
  function syncFromUrl() {
    var params = new URLSearchParams(window.location.search);
    var sources = (params.get("source") || "").split(",");
    chips.forEach(function (chip) {
      var active = sources.indexOf(chip.dataset.source) !== -1;
      chip.setAttribute("aria-pressed", active ? "true" : "false");
      chip.classList.toggle("is-active", active);
    });
    if (search) search.value = params.get("q") || "";
  }

  chips.forEach(function (chip) {
    chip.addEventListener("click", function (event) {
      event.preventDefault();
      var active = chip.getAttribute("aria-pressed") === "true";
      chip.setAttribute("aria-pressed", active ? "false" : "true");
      chip.classList.toggle("is-active", !active);
      apply();
    });
  });

  if (search) {
    search.addEventListener("input", function () {
      window.clearTimeout(searchTimer);
      searchTimer = window.setTimeout(apply, 250);
    });
  }

  var form = filters.querySelector(".filter-search-form");
  if (form) {
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      window.clearTimeout(searchTimer);
      apply();
    });
  }

  window.addEventListener("popstate", function () {
    syncFromUrl();
    refresh();
  });
})();
