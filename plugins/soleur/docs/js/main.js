// Mobile nav toggle
document.addEventListener('DOMContentLoaded', function () {
  var toggle = document.querySelector('.nav-toggle');
  var links = document.querySelector('.nav-links');

  if (toggle && links) {
    toggle.addEventListener('click', function () {
      links.classList.toggle('open');
    });
  }

  // Sidebar active state based on scroll
  var sidebarLinks = document.querySelectorAll('.sidebar-links a[href^="#"]');
  if (sidebarLinks.length > 0) {
    var sections = [];
    sidebarLinks.forEach(function (link) {
      var id = link.getAttribute('href').slice(1);
      var el = document.getElementById(id);
      if (el) sections.push({ link: link, el: el });
    });

    window.addEventListener('scroll', function () {
      var scrollPos = window.scrollY + 100;
      var active = null;
      sections.forEach(function (s) {
        if (s.el.offsetTop <= scrollPos) active = s;
      });
      sidebarLinks.forEach(function (l) { l.classList.remove('active'); });
      if (active) active.link.classList.add('active');
    });
  }
});
