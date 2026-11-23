{{flutter_js}}
{{flutter_build_config}}

// Give the ground station a different cache key from the retired demo.
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    const entrypoint = new URL(build.mainJsPath, document.baseURI);
    entrypoint.searchParams.set("layout", "ground-station");
    build.mainJsPath = entrypoint.href;
  }
}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
