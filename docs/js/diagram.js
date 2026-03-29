// Workflow diagram tab switching

document.addEventListener('DOMContentLoaded', () => {
  const tabs = document.querySelectorAll('.workflow-tab');
  const panels = document.querySelectorAll('.workflow-panel');

  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      const target = tab.dataset.tab;

      // Update active tab
      tabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');

      // Update active panel
      panels.forEach(p => {
        p.classList.remove('active');
        if (p.id === target) p.classList.add('active');
      });

      // Re-trigger step animations in the new panel
      const activePanel = document.getElementById(target);
      if (activePanel) {
        const steps = activePanel.querySelectorAll('.wf-step');
        steps.forEach(step => step.classList.remove('visible'));
        requestAnimationFrame(() => {
          steps.forEach((step, i) => {
            setTimeout(() => step.classList.add('visible'), i * 120);
          });
        });
      }
    });
  });

  // Monitor dashboard spinner animation
  const spinner = document.getElementById('monitor-spinner');
  if (spinner) {
    const frames = ['\u2808', '\u2818', '\u2838', '\u2834', '\u2826', '\u2827', '\u2807', '\u280f', '\u2819', '\u2839'];
    let i = 0;
    setInterval(() => {
      spinner.textContent = frames[i % frames.length];
      i++;
    }, 100);
  }

  // Animate progress bar fill
  const progressFill = document.getElementById('progress-fill');
  if (progressFill) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          progressFill.classList.add('animate');
          observer.disconnect();
        }
      });
    }, { threshold: 0.5 });
    observer.observe(progressFill);
  }
});
