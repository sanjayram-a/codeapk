enum ProFeature { terminal, download, projectSizes, background, generic }

extension ProFeatureCopy on ProFeature {
  String get reason => switch (this) {
    ProFeature.terminal => 'Terminal is a Pro feature.',
    ProFeature.download => 'Save and export with Pro.',
    ProFeature.projectSizes => 'See what every project uses.',
    ProFeature.background => 'Keep the server warm longer.',
    ProFeature.generic => 'Unlock everything, once.',
  };
}
