declare const build_environment: string; // this is defined in index.html, and is set during the build process

export const message = 'hello world!';
export const environmentName = build_environment;

export const config = (function() {
    const baseConfig = {
        /* place any common fields here */
    };

    switch(environmentName) {
        case 'prod':
            return { ...baseConfig, /* place any prod-specific fields here */ }
        default:
            return baseConfig;
    }
})();