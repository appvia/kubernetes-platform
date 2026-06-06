/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docs: [
    {
      type: 'doc',
      id: 'index',
      label: 'Overview',
    },
    {
      type: 'category',
      label: 'Architecture',
      items: [
        'architecture/overview',
        'architecture/setup',
        'architecture/system-appsets',
        'architecture/tenant-appsets',
        'architecture/tenant-namespace',
      ],
    },
    {
      type: 'category',
      label: 'Getting Started',
      items: [
        'getting-started/standalone',
        'getting-started/standalone-aws',
        'getting-started/central',
      ],
    },
    {
      type: 'category',
      label: 'Development',
      items: [
        'development/local',
        'development/validation',
        {
          type: 'category',
          label: 'Remote',
          items: [
            'development/overview',
            'development/standalone',
            'development/hub',
          ],
        },
      ],
    },
    {
      type: 'category',
      label: 'Platform',
      items: [
        'platform/overview',
        {
          type: 'category',
          label: 'Addons',
          items: ['catalog/overview', 'catalog/features'],
        },
        {
          type: 'category',
          label: 'Node Pools',
          items: [
            'platform/nodepools/overview',
            'platform/nodepools/karpenter',
          ],
        },
        {
          type: 'category',
          label: 'Notifications',
          items: [
            'platform/notifications/overview',
            'platform/notifications/slack',
          ],
        },
        {
          type: 'category',
          label: 'Security',
          items: [
            {
              type: 'category',
              label: 'Network Security',
              items: [
                'platform/security/cilium',
                'platform/security/cilium-examples',
              ],
            },
            {
              type: 'category',
              label: 'Admission Policy',
              items: [
                'platform/security/kyverno',
                'platform/security/kyverno-policies',
                'platform/security/pod-security',
              ],
            },
            {
              type: "category",
              label: "Permissions",
              items: ["platform/security/cluster-roles"],
            },
            "platform/security/external-secrets",
          ],
        },
        {
          type: 'category',
          label: 'Workloads',
          items: [
            'platform/tenant/applications',
            'platform/tenant/system',
            {
              type: 'category',
              label: 'Autoscaling',
              items: [
                'platform/workloads/autoscaling/overview',
                'platform/workloads/autoscaling/keda',
                'platform/workloads/autoscaling/vpa',
              ],
            },
          ],
        },
      ],
    },
  ],
};

module.exports = sidebars;
