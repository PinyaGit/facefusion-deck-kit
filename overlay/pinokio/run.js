const path = require('path');

module.exports = () =>
{
	const config =
	{
		daemon: true,
		cmd:
		{
			// Quality profiles (Steam Deck-tuned configs)
			'Fast': 'python facefusion.py run --config-path facefusion.fast.ini',
			'Balanced': 'python facefusion.py run --config-path facefusion.balanced.ini',
			'Quality': 'python facefusion.py run --config-path facefusion.quality.ini',
			// Layouts / extras
			'Default': 'python facefusion.py run --config-path facefusion.balanced.ini',
			'Default+Jobs': 'python facefusion.py run --config-path facefusion.balanced.ini --ui-layouts default jobs',
			'Benchmark': 'python facefusion.py run --config-path facefusion.fast.ini --ui-layouts benchmark',
			'Webcam': 'python facefusion.py run --config-path facefusion.fast.ini --ui-layouts webcam'
		},
		run:
		[
			{
				method: 'local.set',
				params:
				{
					mode: '{{ input.mode }}'
				}
			},
			// facefusion-deck-kit: disabled git checkout so NSFW + profile patches persist
			// {
			// 	method: 'shell.run',
			// 	params:
			// 	{
			// 		message: 'git checkout --quiet -- facefusion',
			// 		path: 'facefusion'
			// 	}
			// },
			{
				method: 'shell.run',
				params:
				{
					message: '{{ self.cmd[local.mode] }}',
					path: 'facefusion',
					conda:
					{
						path: path.resolve(__dirname, '.env')
					},
					on:
					[
						{
							event: '/(http:\\/\\/[0-9.:]+)/',
							done: true
						}
					]
				}
			},
			{
				method: 'local.set',
				params:
				{
					url: '{{ input.event[1] || input.event[0] }}'
				}
			}
		]
	};

	return config;
};
