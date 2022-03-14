const webpack = require('webpack')
const { defineConfig } = require('@vue/cli-service')
const BundleAnalyzerPlugin = require('webpack-bundle-analyzer').BundleAnalyzerPlugin
module.exports = defineConfig({
    pages: {
        index: {
            entry: 'src/main.js',
            title: 'ZcashDex',
        },
    },
    transpileDependencies: true,
    configureWebpack: {
        resolve: {
            fallback: {
                crypto: require.resolve('crypto-browserify'),
                stream: require.resolve('stream-browserify'),
                buffer: require.resolve('buffer/'),
            },
        },
        plugins: [
            new webpack.ProvidePlugin({
                Buffer: ['buffer', 'Buffer'],
            }),
            // new BundleAnalyzerPlugin(),
        ],
    },
    css: {
        loaderOptions: {
            postcss: {
            },
        },
    },
})
