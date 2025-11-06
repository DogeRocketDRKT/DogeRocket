/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        cyan: { 400: '#06b6d4', 500: '#0891b2' },
        blue: { 600: '#2563eb' }
      }
    }
  }
};
