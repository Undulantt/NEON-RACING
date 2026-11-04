"""Measure aligned road runs in the existing geographic routes; never changes map data."""
import json, math
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def analyze():
    result = {}
    for path in sorted((ROOT / 'tracks').glob('*.json')):
        data = json.loads(path.read_text(encoding='utf-8'))
        points = data['points_xz']
        spans = []
        start = 0
        length = 0.0
        turning = 0.0
        prior = None
        for index, (a, b) in enumerate(zip(points, points[1:])):
            dx, dz = b[0]-a[0], b[1]-a[1]
            distance = math.hypot(dx, dz)
            if distance < .001:
                continue
            direction = (dx/distance, dz/distance)
            angle = math.acos(max(-1, min(1, sum(x*y for x,y in zip(prior,direction))))) if prior else 0
            if turning + angle > math.radians(12):
                spans.append({'length_m': round(length, 2), 'first_point_index': start, 'last_point_index': index})
                start, length, turning = index, 0.0, 0.0
            else:
                turning += angle
            length += distance
            prior = direction
        spans.append({'length_m': round(length, 2), 'first_point_index': start, 'last_point_index': len(points)-1})
        result[path.stem] = {'criterion': 'At most 12 degrees of cumulative heading change per run; intersections and slopes still exist', 'longest_runs': sorted(spans,key=lambda p:p['length_m'],reverse=True)[:5]}
    (ROOT/'docs/burst_route_geometry.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    for key, value in result.items():
        print(key, value['longest_runs'][0]['length_m'])

if __name__ == '__main__':
    analyze()
