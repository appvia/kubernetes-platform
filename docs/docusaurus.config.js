// @ts-check
const { themes: prismThemes } = require("prism-react-renderer");

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: "Kubernetes Platform",
  tagline: "Built for DevOps, Platform Engineers, and SREs",
  url: "https://appvia.github.io",
  baseUrl: "/kubernetes-platform/",
  onBrokenLinks: "throw",
  onBrokenMarkdownLinks: "warn",
  favicon: "img/favicon.png",
  organizationName: "appvia",
  projectName: "kubernetes-platform",
  trailingSlash: false,
  themes: ["@docusaurus/theme-mermaid"],

  markdown: {
    mermaid: true,
  },

  presets: [
    [
      "classic",
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          sidebarPath: "./sidebars.js",
          routeBasePath: "/",
          editUrl:
            "https://github.com/appvia/kubernetes-platform/edit/main/docs/",
        },
        blog: false,
        theme: {
          customCss: "./src/css/custom.css",
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      colorMode: {
        defaultMode: "light",
        disableSwitch: false,
        respectPrefersColorScheme: true,
      },
      navbar: {
        title: "Kubernetes Platform",
        logo: {
          alt: "Kubernetes Platform Logo",
          src: "img/favicon.png",
        },
        items: [
          {
            type: "docSidebar",
            sidebarId: "docs",
            position: "left",
            label: "Documentation",
          },
          {
            href: "https://github.com/appvia/kubernetes-platform",
            label: "GitHub",
            position: "right",
          },
        ],
      },
      footer: {
        style: "dark",
        links: [
          {
            label: "GitHub",
            href: "https://github.com/appvia",
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} Appvia Ltd.`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
        additionalLanguages: ["yaml", "bash", "shell-session"],
      },
    }),
};

module.exports = config;
